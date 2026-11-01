USE master;
GO

EXECUTE master.dbo.xp_create_subdir 'c:\sqldata';
EXECUTE master.dbo.xp_create_subdir 'c:\sqllog';
GO

IF DB_ID(N'ASADA') IS NULL
BEGIN
    CREATE DATABASE [ASADA]
    ON PRIMARY
    (
        NAME = N'ASADA_Data',
        FILENAME = N'c:\sqldata\ASADA_Data.mdf',
        SIZE = 1GB,
        MAXSIZE = 5GB,
        FILEGROWTH = 128MB
    )
    LOG ON
    (
        NAME = N'ASADA_Log',
        FILENAME = N'c:\sqllog\ASADA_Log.ldf',
        SIZE = 512MB,
        MAXSIZE = 2GB,
        FILEGROWTH = 128MB
    );
END;
GO

ALTER DATABASE [ASADA] SET RECOVERY FULL;
GO

IF DB_ID(N'ASADA_DW') IS NULL
BEGIN
    CREATE DATABASE [ASADA_DW]
    ON PRIMARY
    (
        NAME = N'ASADA_DW_Data',
        FILENAME = N'c:\sqldata\ASADA_DW_Data.mdf',
        SIZE = 512MB,
        MAXSIZE = 2GB,
        FILEGROWTH = 64MB
    )
    LOG ON
    (
        NAME = N'ASADA_DW_Log',
        FILENAME = N'c:\sqllog\ASADA_DW_Log.ldf',
        SIZE = 256MB,
        MAXSIZE = 1GB,
        FILEGROWTH = 64MB
    );
END;
GO

ALTER DATABASE [ASADA_DW] SET RECOVERY SIMPLE;
GO
