SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* =====================================================================
   Script 09: Procedimientos - Usuarios, roles, permisos y bitácora (R6, RA1, RA5)
   ===================================================================== */
USE ASADA;
GO

/* ---------------------------------------------------------------------
   12.9 Bitácora
   --------------------------------------------------------------------- */
-- Punto único para registrar eventos que no provienen de un trigger
-- (inicios de sesión, respaldos, restauraciones, ETL, mantenimiento de la BD).
CREATE OR ALTER PROCEDURE dbo.sp_RegistrarEventoBitacora
    @accion              varchar(15),
    @tabla_afectada      varchar(50)   = NULL,
    @descripcion         varchar(max)  = NULL,
    @id_usuario_sistema  int           = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Bitacora (id_usuario_sistema, fecha_registro, accion, tabla_afectada, descripcion)
    VALUES (COALESCE(@id_usuario_sistema, dbo.fn_UsuarioActual()), GETDATE(), @accion, @tabla_afectada, @descripcion);
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarBitacora
    @id_usuario_sistema  int         = NULL,
    @accion              varchar(15) = NULL,
    @tabla_afectada      varchar(50) = NULL,
    @desde               datetime    = NULL,
    @hasta               datetime    = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT b.id_bitacora, b.fecha_registro, ISNULL(u.nombre_usuario, 'SISTEMA') AS usuario,
           b.accion, b.tabla_afectada, b.descripcion
    FROM dbo.Bitacora b
    LEFT JOIN dbo.Usuario_Sistema u ON u.id_usuario_sistema = b.id_usuario_sistema
    WHERE (@id_usuario_sistema IS NULL OR b.id_usuario_sistema = @id_usuario_sistema)
      AND (@accion             IS NULL OR b.accion = @accion)
      AND (@tabla_afectada     IS NULL OR b.tabla_afectada = @tabla_afectada)
      AND (@desde              IS NULL OR b.fecha_registro >= @desde)
      AND (@hasta              IS NULL OR b.fecha_registro <= @hasta)
    ORDER BY b.fecha_registro DESC, b.id_bitacora DESC;
END;
GO

-- Cantidad de acciones por usuario y tipo de operación en un rango de fechas.
CREATE OR ALTER PROCEDURE dbo.sp_ResumirActividadUsuarios
    @desde datetime,
    @hasta datetime
AS
BEGIN
    SET NOCOUNT ON;

    SELECT ISNULL(u.nombre_usuario, 'SISTEMA') AS usuario, b.accion,
           COUNT(*) AS cantidad, MIN(b.fecha_registro) AS primera, MAX(b.fecha_registro) AS ultima
    FROM dbo.Bitacora b
    LEFT JOIN dbo.Usuario_Sistema u ON u.id_usuario_sistema = b.id_usuario_sistema
    WHERE b.fecha_registro BETWEEN @desde AND @hasta
    GROUP BY ISNULL(u.nombre_usuario, 'SISTEMA'), b.accion
    ORDER BY usuario, cantidad DESC;
END;
GO

/* ---------------------------------------------------------------------
   12.24 Usuario del sistema
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_RegistrarInicioSesion
    @id_usuario_sistema int
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Usuario_Sistema
    SET fecha_ultimo_acceso = GETDATE(), intentos_fallidos = 0
    WHERE id_usuario_sistema = @id_usuario_sistema;
END;
GO

-- Suma un intento fallido y bloquea la cuenta al llegar a 3.
CREATE OR ALTER PROCEDURE dbo.sp_RegistrarIntentoFallido
    @id_usuario_sistema int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @maximo_intentos int = 3;

    UPDATE dbo.Usuario_Sistema
    SET intentos_fallidos = intentos_fallidos + 1,
        activo = CASE WHEN intentos_fallidos + 1 >= @maximo_intentos THEN 0 ELSE activo END
    WHERE id_usuario_sistema = @id_usuario_sistema;
END;
GO

-- Valida las credenciales. Si son correctas, guarda el usuario y el empleado en
-- SESSION_CONTEXT para que los triggers de auditoría sepan quién hace cada cambio.
-- @resultado: 'OK', 'CREDENCIALES_INVALIDAS' o 'USUARIO_BLOQUEADO'.
CREATE OR ALTER PROCEDURE dbo.sp_IniciarSesion
    @nombre_usuario      varchar(50),
    @contrasena          nvarchar(128),
    @id_usuario_sistema  int         = NULL OUTPUT,
    @resultado           varchar(30) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @hash varchar(64), @activo bit, @id_empleado int, @empleado_activo bit;

    SELECT @id_usuario_sistema = u.id_usuario_sistema, @hash = u.contrasena_usuario,
           @activo = u.activo, @id_empleado = u.id_empleado, @empleado_activo = e.activo
    FROM dbo.Usuario_Sistema u
    JOIN dbo.Empleado e ON e.id_empleado = u.id_empleado
    WHERE u.nombre_usuario = @nombre_usuario;

    IF @id_usuario_sistema IS NULL
    BEGIN
        SET @resultado = 'CREDENCIALES_INVALIDAS';
        EXEC dbo.sp_RegistrarEventoBitacora 'LOGIN_FALLIDO', 'Usuario_Sistema',
             'Intento de inicio de sesión con un usuario inexistente.';
        RETURN 1;
    END

    IF @activo = 0 OR @empleado_activo = 0
    BEGIN
        SET @resultado = 'USUARIO_BLOQUEADO';
        EXEC dbo.sp_RegistrarEventoBitacora 'LOGIN_FALLIDO', 'Usuario_Sistema',
             'Intento de inicio de sesión con un usuario inactivo.', @id_usuario_sistema;
        SET @id_usuario_sistema = NULL;
        RETURN 2;
    END

    IF @hash <> dbo.fn_HashContrasena(@nombre_usuario, @contrasena)
    BEGIN
        EXEC dbo.sp_RegistrarIntentoFallido @id_usuario_sistema;
        EXEC dbo.sp_RegistrarEventoBitacora 'LOGIN_FALLIDO', 'Usuario_Sistema',
             'Contraseña incorrecta.', @id_usuario_sistema;
        SET @resultado = 'CREDENCIALES_INVALIDAS';
        SET @id_usuario_sistema = NULL;
        RETURN 1;
    END

    EXEC dbo.sp_RegistrarInicioSesion @id_usuario_sistema;

    EXEC sys.sp_set_session_context @key = N'id_usuario_sistema', @value = @id_usuario_sistema;
    EXEC sys.sp_set_session_context @key = N'id_empleado',        @value = @id_empleado;

    EXEC dbo.sp_RegistrarEventoBitacora 'LOGIN', 'Usuario_Sistema', 'Inicio de sesión exitoso.';

    SET @resultado = 'OK';
    RETURN 0;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_CerrarSesion
AS
BEGIN
    SET NOCOUNT ON;

    IF dbo.fn_UsuarioActual() IS NOT NULL
        EXEC dbo.sp_RegistrarEventoBitacora 'LOGOUT', 'Usuario_Sistema', 'Cierre de sesión.';

    EXEC sys.sp_set_session_context @key = N'id_usuario_sistema', @value = NULL;
    EXEC sys.sp_set_session_context @key = N'id_empleado',        @value = NULL;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_CrearUsuarioSistema
    @id_empleado         int,
    @id_rol              int,
    @nombre_usuario      varchar(50),
    @contrasena          nvarchar(128),
    @id_usuario_sistema  int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @nombre_usuario = LOWER(LTRIM(RTRIM(@nombre_usuario)));

    IF NOT EXISTS (SELECT 1 FROM dbo.Empleado WHERE id_empleado = @id_empleado AND activo = 1)
        THROW 50501, 'El empleado no existe o está inactivo.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Rol WHERE id_rol = @id_rol)
        THROW 50502, 'El rol indicado no existe.', 1;

    IF EXISTS (SELECT 1 FROM dbo.Usuario_Sistema WHERE nombre_usuario = @nombre_usuario)
        THROW 50503, 'El nombre de usuario ya está en uso.', 1;

    IF EXISTS (SELECT 1 FROM dbo.Usuario_Sistema WHERE id_empleado = @id_empleado AND activo = 1)
        THROW 50504, 'El empleado ya tiene un usuario activo.', 1;

    IF dbo.fn_ValidarComplejidadContrasena(@contrasena) = 0
        THROW 50505, 'La contraseña debe tener al menos 8 caracteres, con mayúscula, minúscula, número y símbolo.', 1;

    INSERT INTO dbo.Usuario_Sistema (id_empleado, id_rol, nombre_usuario, contrasena_usuario)
    VALUES (@id_empleado, @id_rol, @nombre_usuario, dbo.fn_HashContrasena(@nombre_usuario, @contrasena));

    SET @id_usuario_sistema = SCOPE_IDENTITY();
END;
GO

-- Si se envía @contrasena_actual se verifica (cambio hecho por el propio usuario);
-- si se omite, es un restablecimiento hecho por el Administrador.
CREATE OR ALTER PROCEDURE dbo.sp_CambiarContrasenaUsuario
    @id_usuario_sistema  int,
    @contrasena_nueva    nvarchar(128),
    @contrasena_actual   nvarchar(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @nombre varchar(50), @hash varchar(64);
    SELECT @nombre = nombre_usuario, @hash = contrasena_usuario
    FROM dbo.Usuario_Sistema WHERE id_usuario_sistema = @id_usuario_sistema;

    IF @nombre IS NULL
        THROW 50506, 'El usuario indicado no existe.', 1;

    IF @contrasena_actual IS NOT NULL AND @hash <> dbo.fn_HashContrasena(@nombre, @contrasena_actual)
        THROW 50507, 'La contraseña actual no es correcta.', 1;

    IF dbo.fn_ValidarComplejidadContrasena(@contrasena_nueva) = 0
        THROW 50505, 'La contraseña debe tener al menos 8 caracteres, con mayúscula, minúscula, número y símbolo.', 1;

    IF @hash = dbo.fn_HashContrasena(@nombre, @contrasena_nueva)
        THROW 50508, 'La nueva contraseña debe ser distinta de la anterior.', 1;

    UPDATE dbo.Usuario_Sistema
    SET contrasena_usuario = dbo.fn_HashContrasena(@nombre, @contrasena_nueva)
    WHERE id_usuario_sistema = @id_usuario_sistema;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_DesactivarUsuarioSistema
    @id_usuario_sistema int
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    UPDATE dbo.Usuario_Sistema SET activo = 0
    WHERE id_usuario_sistema = @id_usuario_sistema AND activo = 1;

    IF @@ROWCOUNT = 0
        THROW 50509, 'El usuario no existe o ya estaba inactivo.', 1;
END;
GO

-- Reactiva una cuenta (por ejemplo, bloqueada por intentos fallidos).
CREATE OR ALTER PROCEDURE dbo.sp_ReactivarUsuarioSistema
    @id_usuario_sistema int
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario_Sistema u JOIN dbo.Empleado e ON e.id_empleado = u.id_empleado
                   WHERE u.id_usuario_sistema = @id_usuario_sistema AND e.activo = 1)
        THROW 50510, 'El usuario no existe o su empleado está inactivo.', 1;

    UPDATE dbo.Usuario_Sistema SET activo = 1, intentos_fallidos = 0
    WHERE id_usuario_sistema = @id_usuario_sistema;
END;
GO

-- Cambia el rol o el empleado asociado. El nombre de usuario no se modifica
-- porque forma parte del hash de la contraseña.
CREATE OR ALTER PROCEDURE dbo.sp_ModificarUsuarioSistema
    @id_usuario_sistema  int,
    @id_rol              int = NULL,
    @id_empleado         int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario_Sistema WHERE id_usuario_sistema = @id_usuario_sistema)
        THROW 50506, 'El usuario indicado no existe.', 1;

    IF @id_rol IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Rol WHERE id_rol = @id_rol)
        THROW 50502, 'El rol indicado no existe.', 1;

    IF @id_empleado IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Empleado WHERE id_empleado = @id_empleado AND activo = 1)
        THROW 50501, 'El empleado no existe o está inactivo.', 1;

    UPDATE dbo.Usuario_Sistema
    SET id_rol = ISNULL(@id_rol, id_rol),
        id_empleado = ISNULL(@id_empleado, id_empleado)
    WHERE id_usuario_sistema = @id_usuario_sistema;
END;
GO

-- RA1: permisos efectivos de un usuario.
CREATE OR ALTER PROCEDURE dbo.sp_ConsultarPermisosUsuario
    @id_usuario_sistema int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT u.nombre_usuario, r.nombre_rol, m.nombre_modulo, p.nombre_permiso
    FROM dbo.Usuario_Sistema u
    JOIN dbo.Rol r          ON r.id_rol = u.id_rol
    JOIN dbo.Rol_permiso rp ON rp.id_rol = r.id_rol
    JOIN dbo.Permiso p      ON p.id_permiso = rp.id_permiso
    JOIN dbo.Modulo m       ON m.id_modulo = p.id_modulo
    WHERE u.id_usuario_sistema = @id_usuario_sistema AND u.activo = 1
    ORDER BY m.nombre_modulo, p.nombre_permiso;
END;
GO

/* ---------------------------------------------------------------------
   12.25 Rol
   --------------------------------------------------------------------- */
-- Si @id_rol es NULL se registra un rol nuevo; si no, se modifica.
CREATE OR ALTER PROCEDURE dbo.sp_GestionarRol
    @nombre_rol varchar(25),
    @id_rol     int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM dbo.Rol WHERE nombre_rol = @nombre_rol AND (@id_rol IS NULL OR id_rol <> @id_rol))
        THROW 50511, 'Ya existe un rol con ese nombre.', 1;

    IF @id_rol IS NULL
    BEGIN
        INSERT INTO dbo.Rol (nombre_rol) VALUES (@nombre_rol);
        SET @id_rol = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE dbo.Rol SET nombre_rol = @nombre_rol WHERE id_rol = @id_rol;
        IF @@ROWCOUNT = 0 THROW 50502, 'El rol indicado no existe.', 1;
    END
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarRoles
AS
BEGIN
    SET NOCOUNT ON;

    SELECT r.id_rol, r.nombre_rol,
           (SELECT COUNT(*) FROM dbo.Usuario_Sistema u WHERE u.id_rol = r.id_rol AND u.activo = 1) AS usuarios_activos,
           (SELECT COUNT(*) FROM dbo.Rol_permiso rp WHERE rp.id_rol = r.id_rol) AS permisos
    FROM dbo.Rol r
    ORDER BY r.nombre_rol;
END;
GO

-- Elimina un rol solo si no tiene usuarios ni permisos asignados.
CREATE OR ALTER PROCEDURE dbo.sp_EliminarRol
    @id_rol int
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM dbo.Usuario_Sistema WHERE id_rol = @id_rol)
        THROW 50512, 'No se puede eliminar: el rol tiene usuarios asignados.', 1;

    IF EXISTS (SELECT 1 FROM dbo.Rol_permiso WHERE id_rol = @id_rol)
        THROW 50513, 'No se puede eliminar: el rol tiene permisos asignados.', 1;

    DELETE FROM dbo.Rol WHERE id_rol = @id_rol;
    IF @@ROWCOUNT = 0 THROW 50502, 'El rol indicado no existe.', 1;

    EXEC dbo.sp_RegistrarEventoBitacora 'DELETE', 'Rol', 'Rol eliminado.';
END;
GO

/* ---------------------------------------------------------------------
   12.26 Permiso / 12.28 Módulo
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_GestionarPermiso
    @id_modulo      int,
    @nombre_permiso varchar(50),
    @id_permiso     int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Modulo WHERE id_modulo = @id_modulo)
        THROW 50514, 'El módulo indicado no existe.', 1;

    IF EXISTS (SELECT 1 FROM dbo.Permiso
               WHERE nombre_permiso = @nombre_permiso AND (@id_permiso IS NULL OR id_permiso <> @id_permiso))
        THROW 50515, 'Ya existe un permiso con ese nombre.', 1;

    IF @id_permiso IS NULL
    BEGIN
        INSERT INTO dbo.Permiso (id_modulo, nombre_permiso) VALUES (@id_modulo, @nombre_permiso);
        SET @id_permiso = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE dbo.Permiso SET id_modulo = @id_modulo, nombre_permiso = @nombre_permiso WHERE id_permiso = @id_permiso;
        IF @@ROWCOUNT = 0 THROW 50516, 'El permiso indicado no existe.', 1;
    END
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarPermisos
AS
BEGIN
    SET NOCOUNT ON;

    SELECT p.id_permiso, p.nombre_permiso, m.id_modulo, m.nombre_modulo
    FROM dbo.Permiso p JOIN dbo.Modulo m ON m.id_modulo = p.id_modulo
    ORDER BY m.nombre_modulo, p.nombre_permiso;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarPermisosPorModulo
    @id_modulo int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT id_permiso, nombre_permiso FROM dbo.Permiso WHERE id_modulo = @id_modulo ORDER BY nombre_permiso;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_GestionarModulo
    @nombre_modulo varchar(50),
    @id_modulo     int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM dbo.Modulo WHERE nombre_modulo = @nombre_modulo AND (@id_modulo IS NULL OR id_modulo <> @id_modulo))
        THROW 50517, 'Ya existe un módulo con ese nombre.', 1;

    IF @id_modulo IS NULL
    BEGIN
        INSERT INTO dbo.Modulo (nombre_modulo) VALUES (@nombre_modulo);
        SET @id_modulo = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE dbo.Modulo SET nombre_modulo = @nombre_modulo WHERE id_modulo = @id_modulo;
        IF @@ROWCOUNT = 0 THROW 50514, 'El módulo indicado no existe.', 1;
    END
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarModulos
AS
BEGIN
    SET NOCOUNT ON;
    SELECT id_modulo, nombre_modulo FROM dbo.Modulo ORDER BY nombre_modulo;
END;
GO

/* ---------------------------------------------------------------------
   12.27 Rol_permiso
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_AsignarPermisoRol
    @id_rol     int,
    @id_permiso int
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Rol WHERE id_rol = @id_rol)
        THROW 50502, 'El rol indicado no existe.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Permiso WHERE id_permiso = @id_permiso)
        THROW 50516, 'El permiso indicado no existe.', 1;

    IF EXISTS (SELECT 1 FROM dbo.Rol_permiso WHERE id_rol = @id_rol AND id_permiso = @id_permiso)
        THROW 50518, 'El rol ya tiene ese permiso.', 1;

    INSERT INTO dbo.Rol_permiso (id_rol, id_permiso) VALUES (@id_rol, @id_permiso);
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_QuitarPermisoRol
    @id_rol     int,
    @id_permiso int
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DELETE FROM dbo.Rol_permiso WHERE id_rol = @id_rol AND id_permiso = @id_permiso;

    IF @@ROWCOUNT = 0
        THROW 50519, 'El rol no tiene asignado ese permiso.', 1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ConsultarPermisosPorRol
    @id_rol int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT rp.id_rol_permiso, m.nombre_modulo, p.id_permiso, p.nombre_permiso
    FROM dbo.Rol_permiso rp
    JOIN dbo.Permiso p ON p.id_permiso = rp.id_permiso
    JOIN dbo.Modulo  m ON m.id_modulo = p.id_modulo
    WHERE rp.id_rol = @id_rol
    ORDER BY m.nombre_modulo, p.nombre_permiso;
END;
GO
