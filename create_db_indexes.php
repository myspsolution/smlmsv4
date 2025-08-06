#!/usr/bin/env php
<?php

/**
 * PHP CLI script to generate CREATE INDEX statements for a MySQL or PostgreSQL database
 * and optionally execute them. By default, it only writes them to /tmp.
 *
 * Usage:
 *   create_db_indexes.php <env_file_or_domain> [execute]
 *
 * If <env_file_or_domain> is an existing file path, it is used directly.
 * Otherwise, the script uses /var/www/html/<domain>/.env.
 *
 * Use the optional "execute" argument to also run the generated .sql statements.
 */

// === COMMONS ===

if ($argc < 2 || $argc > 3) {
    fwrite(STDERR, "Usage:\n");
    fwrite(STDERR, "  php create_db_indexes.php [laravel_env_file_location] [execute]\n");
    fwrite(STDERR, "  - If [execute] is specified, it will run the statements.\n");
    exit(1);
}

$arg      = $argv[1];
$doExecute = (isset($argv[2]) && $argv[2] === 'execute');

/**
 * parseEnvFile
 * Reads a .env-style file (KEY=VAL) into an associative array.
 */
function parseEnvFile($filePath)
{
    if (!file_exists($filePath)) {
        fwrite(STDERR, "Error: File not found - {$filePath}\n");
        exit(1);
    }

    $params = [];
    $lines  = file($filePath, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);

    foreach ($lines as $line) {
        if (strpos(trim($line), '#') === 0) continue;
        $parts = explode('=', $line, 2);
        if (count($parts) === 2) {
            [$key, $value] = $parts;
            $key   = trim($key);
            $value = trim($value);
            $value = trim($value, "'\"");
            $params[$key] = $value;
        }
    }
    return $params;
}

// 1. Figure out the correct .env file path
if (is_file($arg)) {
    $envFilePath = realpath($arg);
} else {
    $possiblePaths = [
        "/var/www/html/{$arg}/.env",
        "/var/www/html/{$arg}.backend/.env",
    ];
    $envFilePath = null;
    foreach ($possiblePaths as $path) {
        if (file_exists($path)) {
            $envFilePath = $path;
            break;
        }
    }
    if (!$envFilePath) {
        fwrite(STDERR, "Error: No .env or backend.env file found for '{$arg}'.\n");
        exit(1);
    }
}

// 2. Parse the .env file
$dbParams = parseEnvFile($envFilePath);

// 3. Basic checks on required fields
$requiredKeys = ["DB_CONNECTION", "DB_HOST", "DB_PORT", "DB_DATABASE", "DB_USERNAME", "DB_PASSWORD"];
foreach ($requiredKeys as $rk) {
    if (empty($dbParams[$rk])) {
        fwrite(STDERR, "Error: Missing or empty '{$rk}' in .env file.\n");
        exit(1);
    }
}

$dbConnection = strtolower($dbParams["DB_CONNECTION"]);
if (!in_array($dbConnection, ["mysql", "pgsql"], true)) {
    fwrite(STDERR, "Error: DB_CONNECTION must be either 'mysql' or 'pgsql'.\n");
    exit(1);
}

// === CONNECTIONS ===

if ($dbConnection === 'mysql') {
    $conn = @new mysqli(
        $dbParams["DB_HOST"],
        $dbParams["DB_USERNAME"],
        $dbParams["DB_PASSWORD"],
        $dbParams["DB_DATABASE"],
        (int)$dbParams["DB_PORT"]
    );
    if ($conn->connect_error) {
        fwrite(STDERR, "Error: Could not connect to MySQL: {$conn->connect_error}\n");
        exit(1);
    }
} else { // pgsql
    $pgConnStr = sprintf(
        "host=%s port=%d dbname=%s user=%s password=%s",
        $dbParams["DB_HOST"],
        $dbParams["DB_PORT"],
        $dbParams["DB_DATABASE"],
        $dbParams["DB_USERNAME"],
        $dbParams["DB_PASSWORD"]
    );
    $conn = @pg_connect($pgConnStr);
    if (!$conn) {
        fwrite(STDERR, "Error: Could not connect to PostgreSQL.\n");
        exit(1);
    }
}

// === TABLES ===

$tables = [];
if ($dbConnection === 'mysql') {
    $tablesResult = $conn->query("SHOW TABLES");
    if (!$tablesResult) {
        fwrite(STDERR, "Error: Could not retrieve tables - {$conn->error}\n");
        $conn->close();
        exit(1);
    }
    while ($row = $tablesResult->fetch_array(MYSQLI_NUM)) {
        $tables[] = $row[0];
    }
    $tablesResult->free();
} else { // pgsql
    $sql = "SELECT tablename FROM pg_tables WHERE schemaname = 'public'";
    $result = pg_query($conn, $sql);
    if (!$result) {
        fwrite(STDERR, "Error: Could not retrieve tables - ".pg_last_error($conn)."\n");
        pg_close($conn);
        exit(1);
    }
    while ($row = pg_fetch_assoc($result)) {
        $tables[] = $row['tablename'];
    }
    pg_free_result($result);
}

// === OUTPUT FILE ===

$dbName = preg_replace('/[^A-Za-z0-9_-]+/', '_', $dbParams['DB_DATABASE']); // safe-ish
$indexFilePath = "/tmp/create_indexes_{$dbName}.sql";
$indexFileHandle = @fopen($indexFilePath, 'w');
if (!$indexFileHandle) {
    fwrite(STDERR, "Error: Unable to open file for writing: {$indexFilePath}\n");
    if ($dbConnection === 'mysql') $conn->close();
    else pg_close($conn);
    exit(1);
}

$lineCount = 0;

// === TYPE NORMALIZATION ===
function normalize_type($db, $type) {
    $type = strtolower($type);
    if ($db === 'mysql') {
        // Strip params, e.g. varchar(255)
        $type = preg_replace('/\(.*/', '', $type);
        return strtoupper($type);
    } else { // pgsql
        $map = [
            'character varying' => 'VARCHAR',
            'varchar' => 'VARCHAR',
            'character' => 'CHAR',
            'char' => 'CHAR',
            'text' => 'TEXT',
            'smallint' => 'SMALLINT',
            'integer' => 'INTEGER',
            'bigint' => 'BIGINT',
            'boolean' => 'BOOLEAN',
            'bool' => 'BOOLEAN',
            'date' => 'DATE',
            'timestamp without time zone' => 'TIMESTAMP',
            'timestamp with time zone' => 'TIMESTAMP',
            'enum' => 'ENUM',
            // Add other mappings as needed
        ];
        return isset($map[$type]) ? $map[$type] : strtoupper($type);
    }
}

// === MAIN LOOP ===
foreach ($tables as $tableName) {
    // --- Gather indexed columns
    $alreadyIndexedColumns = [];

    if ($dbConnection === 'mysql') {
        $indexRes = $conn->query("SHOW INDEX FROM `{$tableName}`");
        if ($indexRes) {
            while ($idxRow = $indexRes->fetch_assoc()) {
                $colName = strtolower($idxRow['Column_name']);
                $alreadyIndexedColumns[$colName] = true;
            }
            $indexRes->free();
        }
    } else { // pgsql
        $sql = "SELECT a.attname as column_name
                FROM pg_class t, pg_class i, pg_index ix, pg_attribute a
                WHERE t.oid = ix.indrelid
                  AND i.oid = ix.indexrelid
                  AND a.attrelid = t.oid
                  AND a.attnum = ANY(ix.indkey)
                  AND t.relkind = 'r'
                  AND t.relname = '{$tableName}'";
        $indexRes = pg_query($conn, $sql);
        if ($indexRes) {
            while ($idxRow = pg_fetch_assoc($indexRes)) {
                $colName = strtolower($idxRow['column_name']);
                $alreadyIndexedColumns[$colName] = true;
            }
            pg_free_result($indexRes);
        }
    }

    // --- Gather columns
    $columns = [];
    if ($dbConnection === 'mysql') {
        $colsRes = $conn->query("SHOW COLUMNS FROM `{$tableName}`");
        if (!$colsRes) {
            fwrite(STDERR, "Warning: Could not get columns for {$tableName} - {$conn->error}\n");
            continue;
        }
        while ($colRow = $colsRes->fetch_assoc()) {
            $fieldName = $colRow['Field'];
            $typeRaw = $colRow['Type'];
            $columns[] = [
                'name' => $fieldName,
                'type' => normalize_type('mysql', $typeRaw),
            ];
        }
        $colsRes->free();
    } else { // pgsql
        $colsRes = pg_query($conn, "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = '{$tableName}'");
        if (!$colsRes) {
            fwrite(STDERR, "Warning: Could not get columns for {$tableName} - ".pg_last_error($conn)."\n");
            continue;
        }
        while ($colRow = pg_fetch_assoc($colsRes)) {
            $columns[] = [
                'name' => $colRow['column_name'],
                'type' => normalize_type('pgsql', $colRow['data_type']),
            ];
        }
        pg_free_result($colsRes);
    }

    // --- Index generation logic
    foreach ($columns as $col) {
        $fieldName = $col['name'];
        $fieldType = $col['type'];
        $fieldNameLower = strtolower($fieldName);

        if (isset($alreadyIndexedColumns[$fieldNameLower])) {
            continue;
        }

        $endsWithId   = (substr($fieldNameLower, -3) === '_id');
        $startsWithIs = (substr($fieldNameLower, 0, 3) === 'is_');
        $commonTextCol = in_array($fieldNameLower, ['title','name'], true);

        $indexedTypes = [
            'VARCHAR','CHAR', 'ENUM', 'BOOL','BOOLEAN','TINYINT','SMALLINT','MEDIUMINT','INT','INTEGER','BIGINT','DATE','YEAR'
        ];

        $shouldIndex = (
            ($endsWithId   && in_array($fieldType, $indexedTypes, true)) ||
            ($startsWithIs && in_array($fieldType, $indexedTypes, true)) ||
            ($commonTextCol && in_array($fieldType, $indexedTypes, true))
        );

        if ($shouldIndex) {
            // Build index name (MySQL 64, PG 63)
            $indexName = "{$tableName}_{$fieldName}_idx";
            $maxLen = ($dbConnection === 'mysql') ? 64 : 63;
            if (strlen($indexName) > $maxLen) {
                $hash = md5("{$tableName}_{$fieldName}");
                $indexName = "{$hash}_idx";
            }

            if ($dbConnection === 'mysql') {
                $createStmt = "CREATE INDEX `{$indexName}` ON `{$tableName}` (`{$fieldName}`);\n";
            } else {
                // For PostgreSQL: use double quotes
                $createStmt = "CREATE INDEX \"{$indexName}\" ON \"{$tableName}\" (\"{$fieldName}\");\n";
            }

            fwrite($indexFileHandle, $createStmt);
            $lineCount++;
        }
    }
}
fclose($indexFileHandle);

if ($lineCount === 0) {
    echo "No new indexes needed.\n";
    if ($dbConnection === 'mysql') $conn->close();
    else pg_close($conn);
    exit(0);
}

echo "Created {$lineCount} 'CREATE INDEX' statements in:\n  {$indexFilePath}\n";

// === EXECUTE MODE ===
if ($doExecute) {
    echo "\n[EXECUTE MODE] Executing the generated statements...\n\n";
    $lines = file($indexFilePath, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);

    foreach ($lines as $sqlStatement) {
        $sqlStatement = trim($sqlStatement, "; \t\r\n");
        if ($sqlStatement === '') continue;

        if ($dbConnection === 'mysql') {
            $res = $conn->query($sqlStatement);
            if ($res === false) {
                echo "[ERROR] $sqlStatement\nMySQL error: " . $conn->error . "\nContinuing...\n";
            } else {
                echo "[OK] $sqlStatement\n";
            }
        } else {
            $res = pg_query($conn, $sqlStatement);
            if ($res === false) {
                echo "[ERROR] $sqlStatement\nPGSQL error: " . pg_last_error($conn) . "\nContinuing...\n";
            } else {
                echo "[OK] $sqlStatement\n";
                if (is_resource($res)) pg_free_result($res);
            }
        }
    }
} else {
   echo "Use command:\n";
   echo "cat {$indexFilePath}\n";
   echo "to see the content of db index creator sql file\n";
}

if ($dbConnection === 'mysql') $conn->close();
else pg_close($conn);
echo "\nDone.\n";
exit(0);
