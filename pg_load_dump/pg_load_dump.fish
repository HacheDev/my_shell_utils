function pg_load_dump
    set DB $argv[1]
    set DUMP $argv[2]
    set USER $argv[3]
    set PASSWORD $argv[4]

    if test -z "$DB"; or test -z "$DUMP"
        echo "Usage: pg_load_dump <db_name> <dump_path> [user] [password]"
        return 1
    end

    if not test -f $DUMP
        echo "Dump file not found: $DUMP"
        return 1
    end

    if test -z "$USER"
        set USER $DB
    end

    if test -z "$PASSWORD"
        set PASSWORD $USER
    end

    set CLEAN /tmp/"$DB"_clean.sql

    echo "Creating/updating PostgreSQL user '$USER'..."

    sudo -u postgres psql -v ON_ERROR_STOP=1 -c "
DO \$\$
BEGIN
    IF NOT EXISTS (
        SELECT FROM pg_roles WHERE rolname = '$USER'
    ) THEN
        CREATE USER $USER WITH LOGIN PASSWORD '$PASSWORD';
    ELSE
        ALTER USER $USER WITH PASSWORD '$PASSWORD';
    END IF;
END
\$\$;
"; or return 1

    sudo -u postgres psql -v ON_ERROR_STOP=1 -c "ALTER USER $USER CREATEDB;"; or return 1

    echo "Dropping database '$DB' if it exists..."

    sudo -u postgres psql -v ON_ERROR_STOP=1 -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB' AND pid <> pg_backend_pid();"; or return 1
    sudo -u postgres psql -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS $DB;"; or return 1

    echo "Creating clean database '$DB'..."

    sudo -u postgres psql -v ON_ERROR_STOP=1 -c "CREATE DATABASE $DB OWNER $USER;"; or return 1
    sudo -u postgres psql -v ON_ERROR_STOP=1 -c "GRANT ALL PRIVILEGES ON DATABASE $DB TO $USER;"; or return 1

    echo "Cleaning dump ownership/role references..."

    sed -E \
        -e "s/OWNER TO [^;]+/OWNER TO $USER/g" \
        -e "s/TO kaizen_prod_psql/TO $USER/g" \
        -e "s/FROM kaizen_prod_psql/FROM $USER/g" \
        -e "s/TO iman_portal_cliente/TO $USER/g" \
        -e "s/FROM iman_portal_cliente/FROM $USER/g" \
        $DUMP > $CLEAN; or return 1

    echo "Importing dump into '$DB'..."

    sudo -u postgres psql -v ON_ERROR_STOP=1 -d $DB -f $CLEAN; or return 1

    echo "Fixing privileges..."

    sudo -u postgres psql -v ON_ERROR_STOP=1 -d $DB -c "GRANT ALL PRIVILEGES ON SCHEMA public TO $USER;"; or return 1
    sudo -u postgres psql -v ON_ERROR_STOP=1 -d $DB -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $USER;"; or return 1
    sudo -u postgres psql -v ON_ERROR_STOP=1 -d $DB -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $USER;"; or return 1
    sudo -u postgres psql -v ON_ERROR_STOP=1 -d $DB -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $USER;"; or return 1
    sudo -u postgres psql -v ON_ERROR_STOP=1 -d $DB -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $USER;"; or return 1

    echo "Done. Database '$DB' loaded from '$DUMP'."
end
