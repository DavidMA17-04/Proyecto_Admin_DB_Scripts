SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* =====================================================================
   Script 18: Mecanismos de testeo (R7)
   - sp_CargarDatosPrueba : carga un conjunto controlado de datos de prueba.
   - sp_LimpiarDatosPrueba: elimina esos datos y deja el entorno como estaba.
   - sp_EjecutarPruebas   : ejecuta los casos de prueba. Cada caso corre dentro
                            de una transacción que se revierte (ROLLBACK), así
                            que no deja cambios en los datos.
   Los datos de prueba se identifican por:
     abonados  -> correo que termina en '@prueba.asada'
     empleados -> cédula que empieza con '9000000'
     medidores -> número de serie que empieza con 'PRB-'
   ===================================================================== */
USE ASADA;
GO

/* ---------------------------------------------------------------------
   Carga de datos de prueba
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_CargarDatosPrueba
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM dbo.Abonado_Fisico WHERE correo_electronico LIKE '%@prueba.asada')
        THROW 51001, 'Ya hay datos de prueba cargados. Ejecute sp_LimpiarDatosPrueba primero.', 1;

    DECLARE @tarifa_res int, @tarifa_com int, @fontanero1 int, @fontanero2 int,
            @a1 int, @a2 int, @a3 int, @j1 int, @c int, @m int, @i int, @k int,
            @fecha datetime, @lectura decimal(10,2), @id_lectura int, @id_factura int,
            @id_incidencia int, @id_mant int, @tipo varchar(10), @efectivo int;

    SELECT @tarifa_res = t.id_tarifa FROM dbo.Tarifa t JOIN dbo.Tipo_Tarifa tt ON tt.id_tipo_tarifa = t.id_tipo_tarifa WHERE tt.nombre_tarifa = 'Residencial';
    SELECT @tarifa_com = t.id_tarifa FROM dbo.Tarifa t JOIN dbo.Tipo_Tarifa tt ON tt.id_tipo_tarifa = t.id_tipo_tarifa WHERE tt.nombre_tarifa = 'Comercial';
    SELECT @efectivo = id_metodo_pago FROM dbo.Metodo_Pago WHERE nombre_metodo = 'Efectivo';

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Empleados (fontaneros)
        EXEC dbo.sp_AgregarEmpleado @cedula = '900000001', @nombre_empleado = 'Carlos', @apellido1_empleado = 'Prueba',
             @apellido2_empleado = 'Uno', @puesto = 'Fontanero', @telefono = '8800-0001', @id_empleado = @fontanero1 OUTPUT;
        EXEC dbo.sp_AgregarEmpleado @cedula = '900000002', @nombre_empleado = 'Ana', @apellido1_empleado = 'Prueba',
             @apellido2_empleado = 'Dos', @puesto = 'Fontanero', @telefono = '8800-0002', @id_empleado = @fontanero2 OUTPUT;

        -- Abonados
        EXEC dbo.sp_Nuevo_Abonado @tipo_identificacion = 'FISICA', @numero_identidad = '901000001', @nombre = 'María',
             @apellido1 = 'Rodríguez', @apellido2 = 'Prueba', @fecha_nacimiento = '1980-03-15',
             @direccion = 'Nicoya, Barrio Prueba casa 1', @telefono = '8811-0001', @correo_electronico = 'maria@prueba.asada',
             @id_abonado = @a1 OUTPUT, @tipo_abonado = @tipo OUTPUT;
        EXEC dbo.sp_Nuevo_Abonado @tipo_identificacion = 'FISICA', @numero_identidad = '901000002', @nombre = 'José',
             @apellido1 = 'Vargas', @apellido2 = 'Prueba', @fecha_nacimiento = '1975-08-02',
             @direccion = 'Nicoya, Barrio Prueba casa 2', @telefono = '8811-0002', @correo_electronico = 'jose@prueba.asada',
             @id_abonado = @a2 OUTPUT, @tipo_abonado = @tipo OUTPUT;
        EXEC dbo.sp_Nuevo_Abonado @tipo_identificacion = 'FISICA', @numero_identidad = '901000003', @nombre = 'Lucía',
             @apellido1 = 'Mora', @apellido2 = 'Prueba', @fecha_nacimiento = '1990-11-20',
             @direccion = 'Mansión, Calle Prueba casa 3', @telefono = '8811-0003', @correo_electronico = 'lucia@prueba.asada',
             @id_abonado = @a3 OUTPUT, @tipo_abonado = @tipo OUTPUT;
        EXEC dbo.sp_Nuevo_Abonado @tipo_identificacion = 'JURIDICA', @numero_identidad = '3101900001', @nombre = 'Soda La Prueba S.A.',
             @direccion = 'Nicoya, Centro local 4', @telefono = '2685-0004', @correo_electronico = 'soda@prueba.asada',
             @cedula_representante = '901000004', @nombre_representante = 'Pedro', @apellido1_representante = 'Prueba',
             @id_abonado = @j1 OUTPUT, @tipo_abonado = @tipo OUTPUT;

        -- Conexiones y medidores
        DECLARE @conexiones TABLE (n int, id_conexion int, id_medidor int);

        EXEC dbo.sp_RegistrarConexion 'FISICO', @a1, @tarifa_res, 'Nicoya, Barrio Prueba casa 1', @c OUTPUT;
        EXEC dbo.sp_AsignarMedidorConexion @c, 'PRB-0001', 0, 0, @m OUTPUT;
        INSERT INTO @conexiones VALUES (1, @c, @m);

        EXEC dbo.sp_RegistrarConexion 'FISICO', @a2, @tarifa_res, 'Nicoya, Barrio Prueba casa 2', @c OUTPUT;
        EXEC dbo.sp_AsignarMedidorConexion @c, 'PRB-0002', 0, 0, @m OUTPUT;
        INSERT INTO @conexiones VALUES (2, @c, @m);

        EXEC dbo.sp_RegistrarConexion 'FISICO', @a3, @tarifa_res, 'Mansión, Calle Prueba casa 3', @c OUTPUT;
        EXEC dbo.sp_AsignarMedidorConexion @c, 'PRB-0003', 0, 0, @m OUTPUT;
        INSERT INTO @conexiones VALUES (3, @c, @m);

        EXEC dbo.sp_RegistrarConexion 'JURIDICO', @j1, @tarifa_com, 'Nicoya, Centro local 4', @c OUTPUT;
        EXEC dbo.sp_AsignarMedidorConexion @c, 'PRB-0004', 0, 0, @m OUTPUT;
        INSERT INTO @conexiones VALUES (4, @c, @m);

        -- Seis meses de lecturas (del mes -6 al mes -1), el día 5 de cada mes.
        -- La conexión 3 tiene un consumo muy alto en el último mes (genera alerta).
        SET @i = 1;
        WHILE @i <= 4
        BEGIN
            SELECT @m = id_medidor FROM @conexiones WHERE n = @i;
            SET @lectura = 0;
            SET @k = 6;
            WHILE @k >= 1
            BEGIN
                SET @fecha = DATEADD(MONTH, -@k, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 5));
                SET @lectura += CASE WHEN @i = 3 AND @k = 1 THEN 85
                                     WHEN @i = 4 THEN 40 + @k
                                     ELSE 15 + (@i * 2) + (@k % 3) END;

                EXEC dbo.sp_RegistrarLectura @id_medidor = @m, @lectura_actual = @lectura, @fecha_lectura = @fecha,
                     @id_lectura = @id_lectura OUTPUT;
                EXEC dbo.sp_GenerarFactura @id_lectura = @id_lectura, @id_factura = @id_factura OUTPUT;

                -- Se simula que la factura se emitió al día siguiente de la lectura, con 15 días de plazo.
                UPDATE dbo.Factura
                SET fecha_emision = DATEADD(DAY, 1, @fecha),
                    fecha_vencimiento = CAST(DATEADD(DAY, 16, @fecha) AS date)
                WHERE id_factura = @id_factura;

                -- Pagos: el abonado 1 debe los dos últimos meses, el abonado 2 debe todo,
                -- los demás pagan a tiempo.
                IF @i IN (3, 4) OR (@i = 1 AND @k > 2)
                BEGIN
                    DECLARE @saldo decimal(10,2) = dbo.fn_CalcularSaldoPendiente(@id_factura);
                    DECLARE @fecha_pago date = CAST(DATEADD(DAY, 10, @fecha) AS date);
                    EXEC dbo.sp_RegistrarPago @id_factura = @id_factura, @id_metodo_pago = @efectivo,
                         @monto = @saldo, @fecha_pago = @fecha_pago;
                END

                SET @k -= 1;
            END
            SET @i += 1;
        END

        EXEC dbo.sp_ActualizarFacturasVencidas;

        -- Incidencia en la conexión 3, con un mantenimiento finalizado.
        SELECT @m = id_medidor, @c = id_conexion FROM @conexiones WHERE n = 3;
        EXEC dbo.sp_RegistrarIncidente @id_medidor = @m, @id_tipo_incidencia = 1,
             @descripcion = 'Fuga visible frente al medidor', @ubicacion = 'Acera frontal',
             @id_incidencia = @id_incidencia OUTPUT;
        EXEC dbo.sp_AsignarMantenimiento @id_incidencia = @id_incidencia, @id_empleado = @fontanero1,
             @id_tipo_trabajo = 1, @id_mantenimiento = @id_mant OUTPUT;
        EXEC dbo.sp_CerrarMantenimiento @id_mantenimiento = @id_mant, @detalle = 'Se cambió el empaque de la llave de paso.';

        -- Incidencia abierta en la conexión 1, con un mantenimiento pendiente.
        SELECT @m = id_medidor FROM @conexiones WHERE n = 1;
        EXEC dbo.sp_RegistrarIncidente @id_medidor = @m, @id_tipo_incidencia = 3,
             @descripcion = 'Baja presión en horas de la tarde', @id_incidencia = @id_incidencia OUTPUT;
        EXEC dbo.sp_AsignarMantenimiento @id_incidencia = @id_incidencia, @id_empleado = @fontanero2,
             @id_tipo_trabajo = 2, @id_mantenimiento = @id_mant OUTPUT;

        -- Trabajo para el usuario "fontanero" (si existe), para probar su módulo de campo:
        -- una incidencia asignada (Programado) y un mantenimiento preventivo En proceso.
        DECLARE @fontanero_usuario int;
        SELECT @fontanero_usuario = u.id_empleado
        FROM dbo.Usuario_Sistema u JOIN dbo.Empleado e ON e.id_empleado = u.id_empleado
        WHERE u.nombre_usuario = 'fontanero' AND e.activo = 1;

        IF @fontanero_usuario IS NOT NULL
        BEGIN
            SELECT @m = id_medidor FROM @conexiones WHERE n = 2;
            EXEC dbo.sp_RegistrarIncidente @id_medidor = @m, @id_tipo_incidencia = 1,
                 @descripcion = 'Fuga en la tubería de la acera', @ubicacion = 'Frente a la casa 2',
                 @id_incidencia = @id_incidencia OUTPUT;
            EXEC dbo.sp_AsignarMantenimiento @id_incidencia = @id_incidencia, @id_empleado = @fontanero_usuario,
                 @id_tipo_trabajo = 1, @descripcion = 'Reparar fuga reportada por el abonado',
                 @id_mantenimiento = @id_mant OUTPUT;

            SELECT @c = id_conexion FROM @conexiones WHERE n = 4;
            EXEC dbo.sp_ProgramarMantenimiento @id_empleado = @fontanero_usuario, @id_tipo_trabajo = 2,
                 @id_conexion = @c, @descripcion = 'Revisión preventiva del medidor comercial',
                 @id_mantenimiento = @id_mant OUTPUT;
            EXEC dbo.sp_CambiarEstadoMantenimiento @id_mantenimiento = @id_mant, @nuevo_estado = 'En proceso',
                 @anotacion = 'Se inició la revisión.';
        END

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH

    -- Recargos sobre las facturas vencidas (fuera de la transacción, factura por factura).
    EXEC dbo.sp_AplicarRecargosMoraMasivo;

    SELECT 'Datos de prueba cargados' AS resultado,
           (SELECT COUNT(*) FROM dbo.Lectura l JOIN dbo.Medidor m ON m.id_medidor = l.id_medidor WHERE m.numero_serie LIKE 'PRB-%') AS lecturas,
           (SELECT COUNT(*) FROM dbo.vw_UsuariosMorosos WHERE identificacion IN ('901000001', '901000002')) AS conexiones_morosas,
           (SELECT COUNT(*) FROM dbo.vw_AlertasActivas WHERE medidor LIKE 'PRB-%') AS alertas_consumo;
END;
GO

/* ---------------------------------------------------------------------
   Limpieza de datos de prueba
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_LimpiarDatosPrueba
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @conexiones TABLE (id int PRIMARY KEY);
    DECLARE @medidores  TABLE (id int PRIMARY KEY);
    DECLARE @lecturas   TABLE (id int PRIMARY KEY);
    DECLARE @facturas   TABLE (id int PRIMARY KEY);
    DECLARE @incidencias TABLE (id int PRIMARY KEY);
    DECLARE @mants      TABLE (id int PRIMARY KEY);

    INSERT INTO @conexiones
    SELECT c.id_conexion FROM dbo.Conexion c
    LEFT JOIN dbo.Abonado_Fisico   f ON f.id_abonado_fisico = c.id_abonado_fisico
    LEFT JOIN dbo.Abonado_Juridico j ON j.id_abonado_juridico = c.id_abonado_juridico
    WHERE f.correo_electronico LIKE '%@prueba.asada' OR j.correo_electronico LIKE '%@prueba.asada';

    INSERT INTO @medidores   SELECT id_medidor    FROM dbo.Medidor    WHERE id_conexion IN (SELECT id FROM @conexiones) OR numero_serie LIKE 'PRB-%';
    INSERT INTO @lecturas    SELECT id_lectura    FROM dbo.Lectura    WHERE id_medidor IN (SELECT id FROM @medidores);
    INSERT INTO @facturas    SELECT id_factura    FROM dbo.Factura    WHERE id_lectura IN (SELECT id FROM @lecturas);
    INSERT INTO @incidencias SELECT id_incidencia FROM dbo.Incidencia WHERE id_medidor IN (SELECT id FROM @medidores);
    INSERT INTO @mants       SELECT id_mantenimiento FROM dbo.Mantenimiento
                             WHERE id_conexion IN (SELECT id FROM @conexiones) OR id_incidencia IN (SELECT id FROM @incidencias)
                                OR id_empleado IN (SELECT id_empleado FROM dbo.Empleado WHERE cedula LIKE '9000000%');

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Data Warehouse
        DELETE FROM ASADA_DW.dbo.FACT_PAGO          WHERE id_pago_origen IN (SELECT id_pago FROM dbo.Pago WHERE id_factura IN (SELECT id FROM @facturas));
        DELETE FROM ASADA_DW.dbo.FACT_FACTURACION   WHERE id_factura_origen IN (SELECT id FROM @facturas);
        DELETE FROM ASADA_DW.dbo.FACT_CONSUMO       WHERE id_lectura_origen IN (SELECT id FROM @lecturas);
        DELETE FROM ASADA_DW.dbo.FACT_MANTENIMIENTO WHERE id_mantenimiento_origen IN (SELECT id FROM @mants);
        DELETE FROM ASADA_DW.dbo.FACT_MOROSIDAD     WHERE id_conexion_dw IN (SELECT id_conexion_dw FROM ASADA_DW.dbo.DIM_CONEXION WHERE id_conexion_origen IN (SELECT id FROM @conexiones));

        -- Base transaccional (de hijos a padres)
        DELETE FROM dbo.Alerta_Consumo          WHERE id_lectura IN (SELECT id FROM @lecturas) OR id_incidencia IN (SELECT id FROM @incidencias);
        DELETE FROM dbo.Historial_Mantenimiento WHERE id_mantenimiento IN (SELECT id FROM @mants);
        DELETE FROM dbo.Mantenimiento           WHERE id_mantenimiento IN (SELECT id FROM @mants);
        DELETE FROM dbo.Historial_Incidencia    WHERE id_incidencia IN (SELECT id FROM @incidencias);
        DELETE FROM dbo.Incidencia              WHERE id_incidencia IN (SELECT id FROM @incidencias);
        DELETE FROM dbo.Pago                    WHERE id_factura IN (SELECT id FROM @facturas);
        DELETE FROM dbo.Recargo_mora            WHERE id_factura IN (SELECT id FROM @facturas);
        DELETE FROM dbo.Factura                 WHERE id_factura IN (SELECT id FROM @facturas);
        DELETE FROM dbo.Lectura                 WHERE id_lectura IN (SELECT id FROM @lecturas);

        -- El trigger INSTEAD OF DELETE convierte el borrado de medidores en baja lógica;
        -- para limpiar las pruebas se desactiva temporalmente.
        DISABLE TRIGGER dbo.trg_ImpedirEliminarMedidor ON dbo.Medidor;
        DELETE FROM dbo.Medidor WHERE id_medidor IN (SELECT id FROM @medidores);
        ENABLE TRIGGER dbo.trg_ImpedirEliminarMedidor ON dbo.Medidor;

        DELETE FROM dbo.Conexion         WHERE id_conexion IN (SELECT id FROM @conexiones);
        DELETE FROM dbo.Abonado_Fisico   WHERE correo_electronico LIKE '%@prueba.asada';
        DELETE FROM dbo.Abonado_Juridico WHERE correo_electronico LIKE '%@prueba.asada';
        DELETE FROM dbo.Empleado         WHERE cedula LIKE '9000000%'
                                           AND id_empleado NOT IN (SELECT id_empleado FROM dbo.Usuario_Sistema);

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        ENABLE TRIGGER dbo.trg_ImpedirEliminarMedidor ON dbo.Medidor;
        THROW;
    END CATCH

    EXEC dbo.sp_RegistrarEventoBitacora 'PRUEBAS', NULL, 'Se eliminaron los datos de prueba.';
    SELECT 'Datos de prueba eliminados' AS resultado;
END;
GO

/* ---------------------------------------------------------------------
   Casos de prueba
   Cada caso: BEGIN TRAN -> acción -> verificación -> ROLLBACK.
   Los resultados se guardan en una variable de tabla, que no se ve
   afectada por el ROLLBACK.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_EjecutarPruebas
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @r TABLE (caso varchar(5), modulo varchar(30), descripcion varchar(150), resultado varchar(6), detalle nvarchar(4000));
    DECLARE @id int, @id2 int, @n int, @tipo varchar(10), @v decimal(10,2), @v2 decimal(10,2), @txt varchar(100),
            @m1 int, @m2 int, @m3 int, @c1 int, @c2 int, @a1 int, @tarifa int, @efectivo int, @f_morosa int, @f_vencida int,
            @fontanero int, @rol_fontanero int, @consumo decimal(10,2), @res varchar(30);

    IF NOT EXISTS (SELECT 1 FROM dbo.Medidor WHERE numero_serie = 'PRB-0001')
    BEGIN
        SELECT 'Primero ejecute dbo.sp_CargarDatosPrueba.' AS aviso;
        RETURN;
    END

    SELECT @m1 = id_medidor, @c1 = id_conexion FROM dbo.Medidor WHERE numero_serie = 'PRB-0001';
    SELECT @m2 = id_medidor, @c2 = id_conexion FROM dbo.Medidor WHERE numero_serie = 'PRB-0002';
    SELECT @m3 = id_medidor FROM dbo.Medidor WHERE numero_serie = 'PRB-0003';
    SELECT @a1 = id_abonado_fisico FROM dbo.Abonado_Fisico WHERE numero_identidad = '901000001';
    SELECT @tarifa = id_tarifa FROM dbo.Conexion WHERE id_conexion = @c1;
    SELECT @efectivo = id_metodo_pago FROM dbo.Metodo_Pago WHERE nombre_metodo = 'Efectivo';
    SELECT @fontanero = id_empleado FROM dbo.Empleado WHERE cedula = '900000002';
    SELECT @rol_fontanero = id_rol FROM dbo.Rol WHERE nombre_rol = 'Fontanero';
    SELECT TOP (1) @f_morosa = id_factura FROM dbo.vw_SaldoFactura WHERE id_conexion = @c2 AND saldo > 0 ORDER BY id_factura DESC;
    SELECT TOP (1) @f_vencida = id_factura FROM dbo.vw_SaldoFactura WHERE id_conexion = @c2 AND estado = 'Vencida' ORDER BY id_factura;

    /* ===== Abonados ===== */
    BEGIN TRY
        BEGIN TRAN;
        EXEC dbo.sp_Nuevo_Abonado @tipo_identificacion = 'FISICA', @numero_identidad = '12-34', @nombre = 'X', @apellido1 = 'Y', @direccion = 'Z';
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T01', 'Abonados', 'Rechaza una cédula con formato inválido', 'FALLÓ', 'No se produjo el error esperado');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T01', 'Abonados', 'Rechaza una cédula con formato inválido', IIF(ERROR_NUMBER() = 50101, 'PASÓ', 'FALLÓ'), ERROR_MESSAGE());
    END CATCH

    BEGIN TRY
        BEGIN TRAN;
        EXEC dbo.sp_Nuevo_Abonado @tipo_identificacion = 'FISICA', @numero_identidad = '901000001', @nombre = 'X', @apellido1 = 'Y', @direccion = 'Z';
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T02', 'Abonados', 'Rechaza una cédula duplicada', 'FALLÓ', 'No se produjo el error esperado');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T02', 'Abonados', 'Rechaza una cédula duplicada', IIF(ERROR_NUMBER() = 50102, 'PASÓ', 'FALLÓ'), ERROR_MESSAGE());
    END CATCH

    BEGIN TRY
        BEGIN TRAN;
        EXEC dbo.sp_Nuevo_Abonado @tipo_identificacion = 'FISICA', @numero_identidad = '909999999', @nombre = 'Nuevo',
             @apellido1 = 'Abonado', @direccion = 'Nicoya, Prueba T03', @id_abonado = @id OUTPUT, @tipo_abonado = @tipo OUTPUT;
        SELECT @n = COUNT(*) FROM dbo.Bitacora WHERE tabla_afectada = 'Abonado_Fisico' AND accion = 'INSERT'
                                                 AND descripcion LIKE CONCAT('Alta del abonado físico ', @id, ' %');
        ROLLBACK;
        INSERT @r VALUES ('T03', 'Abonados', 'Registra un abonado físico válido y lo audita en la bitácora',
                          IIF(@id IS NOT NULL AND @tipo = 'FISICO' AND @n = 1, 'PASÓ', 'FALLÓ'), CONCAT('id=', @id, ', bitácora=', @n));
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T03', 'Abonados', 'Registra un abonado físico válido y lo audita en la bitácora', 'FALLÓ', ERROR_MESSAGE());
    END CATCH

    BEGIN TRY
        BEGIN TRAN;
        EXEC dbo.sp_Nuevo_Abonado @tipo_identificacion = 'JURIDICA', @numero_identidad = '3101999999', @nombre = 'Empresa', @direccion = 'Z';
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T04', 'Abonados', 'Exige representante legal para un abonado jurídico', 'FALLÓ', 'No se produjo el error esperado');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T04', 'Abonados', 'Exige representante legal para un abonado jurídico', IIF(ERROR_NUMBER() = 50104, 'PASÓ', 'FALLÓ'), ERROR_MESSAGE());
    END CATCH

    BEGIN TRY
        BEGIN TRAN;
        EXEC dbo.sp_DesactivarAbonado @tipo_abonado = 'FISICO', @id_abonado = @a1;
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T05', 'Abonados', 'No desactiva un abonado con conexiones activas', 'FALLÓ', 'No se produjo el error esperado');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T05', 'Abonados', 'No desactiva un abonado con conexiones activas', IIF(ERROR_NUMBER() = 50109, 'PASÓ', 'FALLÓ'), ERROR_MESSAGE());
    END CATCH

    /* ===== Conexiones y medidores ===== */
    BEGIN TRY
        BEGIN TRAN;
        INSERT INTO dbo.Conexion (id_abonado_fisico, id_abonado_juridico, id_tarifa, ubicacion)
        VALUES (@a1, (SELECT TOP (1) id_abonado_juridico FROM dbo.Abonado_Juridico), @tarifa, 'Prueba T06');
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T06', 'Conexiones', 'CHECK impide una conexión con titular físico y jurídico a la vez', 'FALLÓ', 'Se insertó la fila');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T06', 'Conexiones', 'CHECK impide una conexión con titular físico y jurídico a la vez',
                          IIF(ERROR_NUMBER() = 547 AND ERROR_MESSAGE() LIKE '%ck_AbonadoORjuridico%', 'PASÓ', 'FALLÓ'), ERROR_MESSAGE());
    END CATCH

    BEGIN TRY
        BEGIN TRAN;
        EXEC dbo.sp_RegistrarConexion 'FISICO', @a1, @tarifa, 'nicoya, barrio prueba casa 1';
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T07', 'Conexiones', 'Rechaza dos conexiones para la misma ubicación', 'FALLÓ', 'No se produjo el error esperado');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T07', 'Conexiones', 'Rechaza dos conexiones para la misma ubicación', IIF(ERROR_NUMBER() = 50114, 'PASÓ', 'FALLÓ'), ERROR_MESSAGE());
    END CATCH

    BEGIN TRY
        BEGIN TRAN;
        EXEC dbo.sp_AsignarMedidorConexion @id_conexion = @c1, @numero_serie = 'PRB-T08';
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T08', 'Conexiones', 'Rechaza un segundo medidor activo en la misma conexión', 'FALLÓ', 'No se produjo el error esperado');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T08', 'Conexiones', 'Rechaza un segundo medidor activo en la misma conexión', IIF(ERROR_NUMBER() = 50121, 'PASÓ', 'FALLÓ'), ERROR_MESSAGE());
    END CATCH

    BEGIN TRY
        BEGIN TRAN;
        DELETE FROM dbo.Medidor WHERE id_medidor = @m1;
        SELECT @txt = estado FROM dbo.Medidor WHERE id_medidor = @m1;
        SELECT @n = COUNT(*) FROM dbo.Lectura WHERE id_medidor = @m1;
        ROLLBACK;
        INSERT @r VALUES ('T09', 'Conexiones', 'Un DELETE de medidor se convierte en baja lógica (Retirado)',
                          IIF(@txt = 'Retirado' AND @n > 0, 'PASÓ', 'FALLÓ'), CONCAT('estado=', @txt, ', lecturas conservadas=', @n));
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T09', 'Conexiones', 'Un DELETE de medidor se convierte en baja lógica (Retirado)', 'FALLÓ', ERROR_MESSAGE());
    END CATCH

    /* ===== Lecturas ===== */
    BEGIN TRY
        BEGIN TRAN;
        SET @v = dbo.fn_ObtenerUltimaLectura(@m1);
        SET @v2 = @v - 1;
        EXEC dbo.sp_RegistrarLectura @id_medidor = @m1, @lectura_actual = @v2;
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T10', 'Lecturas', 'Rechaza una lectura menor que la anterior', 'FALLÓ', 'No se produjo el error esperado');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T10', 'Lecturas', 'Rechaza una lectura menor que la anterior', IIF(ERROR_NUMBER() = 50205, 'PASÓ', 'FALLÓ'), ERROR_MESSAGE());
    END CATCH

    BEGIN TRY
        BEGIN TRAN;
        SET @v = dbo.fn_ObtenerUltimaLectura(@m1);
        SET @v2 = @v + 18;
        EXEC dbo.sp_RegistrarLectura @id_medidor = @m1, @lectura_actual = @v2, @id_lectura = @id OUTPUT, @consumo = @consumo OUTPUT;
        SELECT @n = CASE WHEN ultima_lectura = @v2 THEN 1 ELSE 0 END FROM dbo.Medidor WHERE id_medidor = @m1;
        ROLLBACK;
        INSERT @r VALUES ('T11', 'Lecturas', 'Calcula el consumo y actualiza la última lectura del medidor',
                          IIF(@consumo = 18 AND @n = 1, 'PASÓ', 'FALLÓ'), CONCAT('consumo=', @consumo, ', medidor actualizado=', @n));
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T11', 'Lecturas', 'Calcula el consumo y actualiza la última lectura del medidor', 'FALLÓ', ERROR_MESSAGE());
    END CATCH

    BEGIN TRY
        BEGIN TRAN;
        SET @v = dbo.fn_ObtenerUltimaLectura(@m1);
        SET @v2 = @v + 200;
        SET @id = NULL;
        EXEC dbo.sp_RegistrarLectura @id_medidor = @m1, @lectura_actual = @v2, @id_lectura = @id OUTPUT;
        SELECT @n = COUNT(*) FROM dbo.Alerta_Consumo WHERE id_lectura = @id;
        SELECT @txt = n.nombre_nivel FROM dbo.Alerta_Consumo a
        JOIN dbo.Regla_consumo r ON r.id_regla_consumo = a.id_regla_consumo
        JOIN dbo.Nivel_alerta_Consumo n ON n.id_nivel_alerta = r.id_nivel_alerta
        WHERE a.id_lectura = @id;
        ROLLBACK;
        INSERT @r VALUES ('T12', 'Consumo anómalo', 'Un consumo muy superior al promedio genera una sola alerta de nivel Alto',
                          IIF(@n = 1 AND @txt = 'Alto', 'PASÓ', 'FALLÓ'), CONCAT('alertas=', @n, ', nivel=', @txt));
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T12', 'Consumo anómalo', 'Un consumo muy superior al promedio genera una sola alerta de nivel Alto', 'FALLÓ', ERROR_MESSAGE());
    END CATCH

    BEGIN TRY
        BEGIN TRAN;
        SELECT TOP (1) @id = f.id_lectura FROM dbo.Factura f JOIN dbo.Lectura l ON l.id_lectura = f.id_lectura
        WHERE l.id_medidor = @m1 ORDER BY l.fecha_lectura_actual DESC;
        EXEC dbo.sp_ActualizarLectura @id_lectura = @id, @lectura_actual_nueva = 999, @motivo = 'Prueba';
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T13', 'Lecturas', 'No permite corregir una lectura ya facturada', 'FALLÓ', 'No se produjo el error esperado');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T13', 'Lecturas', 'No permite corregir una lectura ya facturada', IIF(ERROR_NUMBER() = 50207, 'PASÓ', 'FALLÓ'), ERROR_MESSAGE());
    END CATCH

    /* ===== Facturación ===== */
    BEGIN TRY
        BEGIN TRAN;
        SET @v = dbo.fn_ObtenerUltimaLectura(@m2);
        SET @v2 = @v + 20;
        EXEC dbo.sp_RegistrarLectura @id_medidor = @m2, @lectura_actual = @v2, @id_lectura = @id OUTPUT;
        EXEC dbo.sp_GenerarFactura @id_lectura = @id, @id_factura = @id2 OUTPUT;
        SELECT @v = f.monto_total, @v2 = t.monto_fijo + 20 * t.monto_por_m3
        FROM dbo.Factura f CROSS JOIN dbo.Tarifa t
        WHERE f.id_factura = @id2 AND t.id_tarifa = (SELECT id_tarifa FROM dbo.Conexion WHERE id_conexion = @c2);
        ROLLBACK;
        INSERT @r VALUES ('T14', 'Facturación', 'La factura cobra monto fijo + consumo × tarifa por m³',
                          IIF(@v = @v2, 'PASÓ', 'FALLÓ'), CONCAT('total=', @v, ', esperado=', @v2));
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T14', 'Facturación', 'La factura cobra monto fijo + consumo × tarifa por m³', 'FALLÓ', ERROR_MESSAGE());
    END CATCH

    BEGIN TRY
        BEGIN TRAN;
        SELECT @id = id_lectura FROM dbo.Factura WHERE id_factura = @f_morosa;
        EXEC dbo.sp_GenerarFactura @id_lectura = @id;
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T15', 'Facturación', 'No genera dos facturas para la misma lectura', 'FALLÓ', 'No se produjo el error esperado');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T15', 'Facturación', 'No genera dos facturas para la misma lectura', IIF(ERROR_NUMBER() = 50210, 'PASÓ', 'FALLÓ'), ERROR_MESSAGE());
    END CATCH

    /* ===== Pagos y mora ===== */
    BEGIN TRY
        BEGIN TRAN;
        SET @v = dbo.fn_CalcularSaldoPendiente(@f_morosa) + 1;
        EXEC dbo.sp_RegistrarPago @id_factura = @f_morosa, @id_metodo_pago = @efectivo, @monto = @v;
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T16', 'Pagos', 'Rechaza un pago mayor que el saldo pendiente', 'FALLÓ', 'No se produjo el error esperado');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T16', 'Pagos', 'Rechaza un pago mayor que el saldo pendiente', IIF(ERROR_NUMBER() = 50305, 'PASÓ', 'FALLÓ'), ERROR_MESSAGE());
    END CATCH

    BEGIN TRY
        BEGIN TRAN;
        SET @v = dbo.fn_CalcularSaldoPendiente(@f_morosa);
        EXEC dbo.sp_RegistrarPago @id_factura = @f_morosa, @id_metodo_pago = @efectivo, @monto = @v, @id_pago = @id OUTPUT;
        SELECT @txt = estado FROM dbo.Factura WHERE id_factura = @f_morosa;
        EXEC dbo.sp_AnularPago @id_pago = @id, @motivo = 'Prueba de anulación';
        SELECT @tipo = estado FROM dbo.Factura WHERE id_factura = @f_morosa;
        ROLLBACK;
        INSERT @r VALUES ('T17', 'Pagos', 'El pago total marca la factura Pagada y al anularlo vuelve a quedar pendiente',
                          IIF(@txt = 'Pagada' AND @tipo IN ('Pendiente', 'Vencida'), 'PASÓ', 'FALLÓ'), CONCAT('tras pagar=', @txt, ', tras anular=', @tipo));
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T17', 'Pagos', 'El pago total marca la factura Pagada y al anularlo vuelve a quedar pendiente', 'FALLÓ', ERROR_MESSAGE());
    END CATCH

    BEGIN TRY
        BEGIN TRAN;
        INSERT INTO dbo.Pago (id_factura, id_metodo_pago, monto) VALUES (@f_morosa, @efectivo, 0);
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T18', 'Pagos', 'CHECK impide pagos con monto cero o negativo', 'FALLÓ', 'Se insertó la fila');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T18', 'Pagos', 'CHECK impide pagos con monto cero o negativo',
                          IIF(ERROR_NUMBER() = 547 AND ERROR_MESSAGE() LIKE '%CK_Pago_MontoPositivo%', 'PASÓ', 'FALLÓ'), ERROR_MESSAGE());
    END CATCH

    BEGIN TRY
        BEGIN TRAN;
        DECLARE @dias int, @pct decimal(5,2), @base decimal(10,2);
        SELECT @dias = DATEDIFF(DAY, fecha_vencimiento, GETDATE()), @base = monto_total - pagado
        FROM dbo.vw_SaldoFactura WHERE id_factura = @f_vencida;
        SET @pct = dbo.fn_CalcularPorcentajeMora(@dias);
        EXEC dbo.sp_CalcularRecargoMora @id_factura = @f_vencida, @id_recargo = @id OUTPUT;
        SELECT @v = monto_recargo, @v2 = porcentaje_aplicado FROM dbo.Recargo_mora WHERE id_recargo = @id;
        SELECT @n = COUNT(*) FROM dbo.Recargo_mora WHERE id_factura = @f_vencida AND estado = 'Aplicado';
        ROLLBACK;
        INSERT @r VALUES ('T19', 'Mora', 'El recargo usa el porcentaje por días de atraso y hay un solo recargo vigente',
                          IIF(@v2 = @pct AND @v = ROUND(@base * @pct / 100, 2) AND @n = 1, 'PASÓ', 'FALLÓ'),
                          CONCAT('días=', @dias, ', %=', @v2, ', monto=', @v, ', vigentes=', @n));
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T19', 'Mora', 'El recargo usa el porcentaje por días de atraso y hay un solo recargo vigente', 'FALLÓ', ERROR_MESSAGE());
    END CATCH

    /* ===== Incidencias y mantenimientos ===== */
    BEGIN TRY
        BEGIN TRAN;
        EXEC dbo.sp_RegistrarIncidente @id_medidor = @m2, @id_tipo_incidencia = 1, @descripcion = 'Fuga en la tubería principal',
             @id_incidencia = @id OUTPUT;
        EXEC dbo.sp_AsignarMantenimiento @id_incidencia = @id, @id_empleado = @fontanero, @id_tipo_trabajo = 1, @id_mantenimiento = @id2 OUTPUT;
        EXEC dbo.sp_CerrarMantenimiento @id_mantenimiento = @id2, @detalle = 'Reparada la fuga';
        SELECT @txt = CONCAT(estado, '/', prioridad) FROM dbo.Incidencia WHERE id_incidencia = @id;
        SELECT @n = COUNT(*) FROM dbo.Historial_Incidencia WHERE id_incidencia = @id;
        SELECT @v = COUNT(*) FROM dbo.Historial_Mantenimiento WHERE id_mantenimiento = @id2;
        ROLLBACK;
        INSERT @r VALUES ('T20', 'Mantenimientos', 'Cerrar el mantenimiento resuelve la incidencia y deja historial',
                          IIF(@txt = 'Resuelta/Alta' AND @n = 3 AND @v = 2, 'PASÓ', 'FALLÓ'),
                          CONCAT('incidencia=', @txt, ', historial incidencia=', @n, ', historial mantenimiento=', @v));
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T20', 'Mantenimientos', 'Cerrar el mantenimiento resuelve la incidencia y deja historial', 'FALLÓ', ERROR_MESSAGE());
    END CATCH

    /* ===== Tarifas ===== */
    BEGIN TRY
        BEGIN TRAN;
        SELECT @v = monto_por_m3 + 10 FROM dbo.Tarifa WHERE id_tarifa = @tarifa;
        EXEC dbo.sp_ModificarTarifa @id_tarifa = @tarifa, @monto_por_m3 = @v;
        SELECT @n = COUNT(*) FROM dbo.Historial_Tarifa WHERE id_tarifa = @tarifa AND monto_por_m3_nuevo = @v;
        ROLLBACK;
        INSERT @r VALUES ('T21', 'Tarifas', 'Modificar una tarifa guarda el cambio en Historial_Tarifa',
                          IIF(@n = 1, 'PASÓ', 'FALLÓ'), CONCAT('registros de historial=', @n));
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T21', 'Tarifas', 'Modificar una tarifa guarda el cambio en Historial_Tarifa', 'FALLÓ', ERROR_MESSAGE());
    END CATCH

    BEGIN TRY
        BEGIN TRAN;
        EXEC dbo.sp_DesactivarTarifa @id_tarifa = @tarifa;
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T22', 'Tarifas', 'No desactiva una tarifa con conexiones activas', 'FALLÓ', 'No se produjo el error esperado');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T22', 'Tarifas', 'No desactiva una tarifa con conexiones activas', IIF(ERROR_NUMBER() = 50604, 'PASÓ', 'FALLÓ'), ERROR_MESSAGE());
    END CATCH

    /* ===== Seguridad ===== */
    BEGIN TRY
        BEGIN TRAN;
        EXEC dbo.sp_CrearUsuarioSistema @id_empleado = @fontanero, @id_rol = @rol_fontanero, @nombre_usuario = 'prueba.debil', @contrasena = N'12345678';
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T23', 'Seguridad', 'Rechaza una contraseña que no cumple la complejidad mínima', 'FALLÓ', 'No se produjo el error esperado');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        INSERT @r VALUES ('T23', 'Seguridad', 'Rechaza una contraseña que no cumple la complejidad mínima', IIF(ERROR_NUMBER() = 50505, 'PASÓ', 'FALLÓ'), ERROR_MESSAGE());
    END CATCH

    BEGIN TRY
        BEGIN TRAN;
        EXEC dbo.sp_CrearUsuarioSistema @id_empleado = @fontanero, @id_rol = @rol_fontanero,
             @nombre_usuario = 'prueba.fontanero', @contrasena = N'Fontanero#2026', @id_usuario_sistema = @id OUTPUT;
        EXEC dbo.sp_IniciarSesion 'prueba.fontanero', N'Fontanero#2026', @id2 OUTPUT, @res OUTPUT;
        SET @txt = @res;
        EXEC dbo.sp_CerrarSesion;
        EXEC dbo.sp_IniciarSesion 'prueba.fontanero', N'incorrecta1', @id2 OUTPUT, @res OUTPUT;
        EXEC dbo.sp_IniciarSesion 'prueba.fontanero', N'incorrecta2', @id2 OUTPUT, @res OUTPUT;
        EXEC dbo.sp_IniciarSesion 'prueba.fontanero', N'incorrecta3', @id2 OUTPUT, @res OUTPUT;
        EXEC dbo.sp_IniciarSesion 'prueba.fontanero', N'Fontanero#2026', @id2 OUTPUT, @res OUTPUT;
        SELECT @n = COUNT(*) FROM dbo.vw_UsuariosBloqueadosPorIntentos WHERE id_usuario_sistema = @id;
        ROLLBACK;
        INSERT @r VALUES ('T24', 'Seguridad', 'Inicia sesión con la clave correcta y bloquea la cuenta tras 3 intentos fallidos',
                          IIF(@txt = 'OK' AND @res = 'USUARIO_BLOQUEADO' AND @n = 1, 'PASÓ', 'FALLÓ'),
                          CONCAT('primer ingreso=', @txt, ', tras 3 fallos=', @res));
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        EXEC dbo.sp_CerrarSesion;
        INSERT @r VALUES ('T24', 'Seguridad', 'Inicia sesión con la clave correcta y bloquea la cuenta tras 3 intentos fallidos', 'FALLÓ', ERROR_MESSAGE());
    END CATCH

    BEGIN TRY
        BEGIN TRAN;
        EXEC dbo.sp_CrearUsuarioSistema @id_empleado = @fontanero, @id_rol = @rol_fontanero,
             @nombre_usuario = 'prueba.auditoria', @contrasena = N'Auditoria#2026', @id_usuario_sistema = @id OUTPUT;
        EXEC dbo.sp_IniciarSesion 'prueba.auditoria', N'Auditoria#2026', @id2 OUTPUT, @res OUTPUT;
        EXEC dbo.sp_ModificarAbonado @tipo_abonado = 'FISICO', @id_abonado = @a1, @telefono = '8899-9999';
        SELECT @n = COUNT(*) FROM dbo.Bitacora
        WHERE id_usuario_sistema = @id AND tabla_afectada = 'Abonado_Fisico' AND descripcion LIKE '%teléfono%8899-9999%';
        EXEC dbo.sp_CerrarSesion;
        ROLLBACK;
        INSERT @r VALUES ('T25', 'Bitácora', 'La bitácora registra quién modificó un abonado y qué cambió',
                          IIF(@n = 1, 'PASÓ', 'FALLÓ'), CONCAT('registros encontrados=', @n));
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        EXEC dbo.sp_CerrarSesion;
        INSERT @r VALUES ('T25', 'Bitácora', 'La bitácora registra quién modificó un abonado y qué cambió', 'FALLÓ', ERROR_MESSAGE());
    END CATCH

    /* ===== Resultados ===== */
    SELECT caso, modulo, descripcion, resultado, detalle FROM @r ORDER BY caso;

    SELECT COUNT(*) AS total_casos,
           SUM(CASE WHEN resultado = 'PASÓ'  THEN 1 ELSE 0 END) AS pasaron,
           SUM(CASE WHEN resultado = 'FALLÓ' THEN 1 ELSE 0 END) AS fallaron
    FROM @r;
END;
GO

DENY EXECUTE ON dbo.sp_CargarDatosPrueba  TO Rol_Operador;
DENY EXECUTE ON dbo.sp_LimpiarDatosPrueba TO Rol_Operador;
DENY EXECUTE ON dbo.sp_EjecutarPruebas    TO Rol_Operador;
GO

/* ---------------------------------------------------------------------
   Uso:
     EXEC dbo.sp_CargarDatosPrueba;
     EXEC dbo.sp_EjecutarPruebas;
     EXEC dbo.sp_EjecutarCargaDW;          -- prueba del ETL con los datos cargados
     EXEC dbo.sp_LimpiarDatosPrueba;
   --------------------------------------------------------------------- */
