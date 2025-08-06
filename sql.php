#!/usr/bin/env php
<?php

if ($argc < 3) {
    fwrite(STDERR, "Usage:\n");
    fwrite(STDERR, "  php sql.php [env_file|domain] \"SQL_STATEMENT\"\n");
    exit(1);
}

$arg = $argv[1];
$sql = $argv[2];

// Find env file (same as before)
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

// Parse env file
function parseEnvFile($filePath)
{
    $params = [];
    $lines  = file($filePath, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        if (strpos(trim($line), '#') === 0) continue;
        $parts = explode('=', $line, 2);
        if (count($parts) === 2) {
            [$key, $value] = $parts;
            $key   = trim($key);
            $value = trim($value, "'\"");
            $params[$key] = $value;
        }
    }
    return $params;
}

$dbParams = parseEnvFile($envFilePath);

// Check required
$requiredKeys = ["DB_CONNECTION", "DB_HOST", "DB_PORT", "DB_DATABASE", "DB_USERNAME", "DB_PASSWORD"];
foreach ($requiredKeys as $rk) {
    if (empty($dbParams[$rk])) {
        fwrite(STDERR, "Error: Missing or empty '{$rk}' in env file.\n");
        exit(1);
    }
}

$dbType = strtolower($dbParams["DB_CONNECTION"]);
if (!in_array($dbType, ["mysql", "pgsql"], true)) {
    fwrite(STDERR, "Error: DB_CONNECTION must be 'mysql' or 'pgsql'.\n");
    exit(1);
}

// Connect and execute
if ($dbType === "mysql") {
    $mysqli = @new mysqli(
        $dbParams["DB_HOST"],
        $dbParams["DB_USERNAME"],
        $dbParams["DB_PASSWORD"],
        $dbParams["DB_DATABASE"],
        (int)$dbParams["DB_PORT"]
    );
    if ($mysqli->connect_error) {
        fwrite(STDERR, "Error: Could not connect to MySQL: {$mysqli->connect_error}\n");
        exit(1);
    }
    $result = $mysqli->query($sql);
    if ($result === false) {
        fwrite(STDERR, "MySQL error: {$mysqli->error}\n");
        $mysqli->close();
        exit(1);
    }
    if ($result === true) {
        echo "OK, affected rows: " . $mysqli->affected_rows . "\n";
    } else {
        // Fetch & print results as table
        $headers = [];
        while ($row = $result->fetch_assoc()) {
            if (!$headers) {
                $headers = array_keys($row);
                echo implode("\t", $headers) . "\n";
            }
            echo implode("\t", $row) . "\n";
        }
        $result->free();
    }
    $mysqli->close();
} else { // pgsql
    $connStr = sprintf(
        "host=%s port=%d dbname=%s user=%s password=%s",
        $dbParams["DB_HOST"],
        $dbParams["DB_PORT"],
        $dbParams["DB_DATABASE"],
        $dbParams["DB_USERNAME"],
        $dbParams["DB_PASSWORD"]
    );
    $pg = @pg_connect($connStr);
    if (!$pg) {
        fwrite(STDERR, "Error: Could not connect to PostgreSQL\n");
        exit(1);
    }
    $result = pg_query($pg, $sql);
    if ($result === false) {
        fwrite(STDERR, "PGSQL error: " . pg_last_error($pg) . "\n");
        pg_close($pg);
        exit(1);
    }
    if (pg_num_fields($result) == 0) {
        // Not a SELECT
        echo "OK, affected rows: " . pg_affected_rows($result) . "\n";
    } else {
        // Fetch & print results as table
        $numFields = pg_num_fields($result);
        $headers = [];
        for ($i = 0; $i < $numFields; $i++) {
            $headers[] = pg_field_name($result, $i);
        }
        echo implode("\t", $headers) . "\n";
        while ($row = pg_fetch_assoc($result)) {
            echo implode("\t", $row) . "\n";
        }
    }
    pg_free_result($result);
    pg_close($pg);
}

exit(0);
