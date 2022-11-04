#!/bin/bash

function get_psql {
    local _db="$1"
    local _query="$2"

    if [[ -z "${_db}" || -z ${_query} ]]; then
        echo "Not enough arguments provided!"
        sleep 1
        exit 1
    fi

    local _res=$(psql -AXtc "${_query}" "${_db}")
    if [[ $? -ne 0 || ${_res} == "" ]]; then
        echo "Execution error on ${_db} - ${_query}"
        sleep 1
        exit 1
    fi

    echo "${_res}"
}

# we try to connect to db powa as the server may restart before that point
echo "Checking if PoWA is setup..."
get_psql "powa" "SELECT 1"

dbname=${BENCH_DB:-pgbench}

echo "Checking if ${dbname} exists..."
nb=$(get_psql "postgres" "SELECT COUNT(*) FROM pg_database WHERE datname = '${dbname}'")
if [[ "$nb" == "0" ]]; then
    echo "Database ${dbname} does not exist"
    if [[ -z "${BENCH_SKIP_INIT}" ]]; then
        echo "Creating database ${dbname}"
        createdb ${dbname}
        if [[ $? -ne 0 ]]; then
            echo "Error trying to create database!"
            sleep 1
            exit 1
        fi
    else
        sleep 1
        exit 1
    fi;
else
    echo "Database ${dbname} already exists"
fi

echo "Checking pgbench tables..."
nb=$(get_psql "${dbname}" "SELECT COUNT(*) FROM pg_class WHERE relname ~ 'pgbench_' AND relkind = 'r'")
if [[ "$nb" == "0" ]]; then
    echo "No table in ${dbname}"
    if [[ -z "${BENCH_SKIP_INIT}" ]]; then
        echo "Waiting a bit and initializing data"
        sleep 5
        pgbench -i -s ${BENCH_SCALE_FACTOR:-10} -d ${dbname}
        if [[ $? -ne 0 ]]; then
            echo "Error trying to initialize data!"
            sleep 1
            exit 1
        fi
    else
        sleep 1
        exit 1
    fi
elif [[ "$nb" != "4" ]]; then
    echo "Missing tables, starting from scratch"
    if [[ -z "${BENCH_SKIP_INIT}" ]]; then
        dropdb ${dbname}
    fi
    sleep 1
    exit 1
fi

echo "Checking content in pgbench tables..."
nb=$(get_psql "${dbname}" "SELECT COUNT(*) FROM pgbench_accounts")
if [[ "$nb" == "0" ]]; then
    echo "No data in pgbench tables on ${dbname}"
    sleep 1
    exit 1
fi

while [[ true ]]; do
    # Set work_mem globally to a sensible random value, to generate some
    # activity for pg_track_settings
    w_m=$((5000 + $RANDOM % 5000))
    psql -c "ALTER SYSTEM SET work_mem = $w_m" postgres
    psql -c "SELECT pg_reload_conf()" postgres

    echo "running pgbench -T ${BENCH_TIME:-60} ${BENCH_FLAG}"
    pgbench -d ${dbname} -T ${BENCH_TIME:-60} ${BENCH_FLAG} >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo "Error running pgbench!"
        sleep 1
        exit 1
    fi
    echo "Sleeping for ${BENCH_SLEEP_TIME:-10}"
    sleep ${BENCH_SLEEP_TIME:-10}
done
