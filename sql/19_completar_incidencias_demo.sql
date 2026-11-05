SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* Complemento: carga incidencias y mantenimientos si 19_datos_demo.sql
   falló en #inc/#prev (Msg 242) pero el resto de la demo ya está (medidores SC-). */
USE ASADA;
GO
SET NOCOUNT ON;
SET DATEFORMAT ymd;
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Medidor WHERE numero_serie LIKE 'SC-%')
BEGIN
    RAISERROR('No hay datos demo (medidores SC-). Ejecute 19_datos_demo.sql primero.', 16, 1);
    SET NOEXEC ON;
END
GO

IF EXISTS (SELECT 1 FROM dbo.Incidencia)
BEGIN
    RAISERROR('Ya existen incidencias. No se ejecutó el complemento.', 16, 1);
    SET NOEXEC ON;
END
GO

DECLARE @admin int, @emp_admin int;
SELECT @admin = id_usuario_sistema, @emp_admin = id_empleado FROM dbo.Usuario_Sistema WHERE nombre_usuario = 'admin';
EXEC sys.sp_set_session_context @key = N'id_usuario_sistema', @value = @admin;
EXEC sys.sp_set_session_context @key = N'id_empleado', @value = @emp_admin;
GO

CREATE TABLE #emp (
    n int PRIMARY KEY, cedula varchar(20), nombre varchar(20), ap1 varchar(20), ap2 varchar(20),
    puesto varchar(20), tel varchar(15), contratado date, usuario varchar(50) NULL, rol varchar(25) NULL,
    id_empleado int NULL);

INSERT INTO #emp (n, cedula, nombre, ap1, ap2, puesto, tel, contratado, usuario, rol) VALUES
 ( 1, '503450781', 'Jorge',      'Matarrita', 'Gutiérrez', 'Fontanero',            '8834-2211', '2019-03-11', 'jorge.matarrita',    'Fontanero'),
 ( 2, '504120339', 'Esteban',    'Obando',    'Rosales',   'Fontanero',            '8712-4490', '2020-07-01', 'esteban.obando',     'Fontanero'),
 ( 3, '502980614', 'Wilberth',   'Chavarría', 'Espinoza',  'Fontanero',            '8590-1173', '2018-01-15', 'wilberth.chavarria', 'Fontanero'),
 ( 4, '505230488', 'Kendall',    'Villegas',  'Juárez',    'Fontanero',            '8467-3320', '2022-02-07', 'kendall.villegas',   'Fontanero'),
 ( 5, '503770925', 'Rafael',     'Baltodano', 'Cubillo',   'Fontanero',            '8355-7781', '2021-05-17', 'rafael.baltodano',   'Fontanero'),
 ( 6, '504660152', 'Minor',      'Angulo',    'Carrillo',  'Fontanero',            '8621-0954', '2023-09-04', 'minor.angulo',       'Fontanero'),
 ( 7, '505010276', 'Danny',      'Ruiz',      'Alvarado',  'Ayudante fontanería',  '8740-6612', '2024-03-18', NULL,                 NULL),
 ( 8, '503110847', 'Óscar',      'Dinarte',   'Pizarro',   'Lector de medidores',  '8813-5539', '2019-10-21', 'oscar.dinarte',      'Fontanero'),
 ( 9, '504890533', 'Yerlin',     'Briceño',   'Mena',      'Lectora de medidores', '8299-4410', '2022-06-13', 'yerlin.briceno',     'Fontanero'),
 (10, '505470190', 'Brayan',     'Cortés',    'Lara',      'Lector de medidores',  '8576-8823', '2025-01-20', NULL,                 NULL),
 (11, '503560712', 'Karla',      'Espinoza',  'Matarrita', 'Cajera',               '8690-3347', '2020-02-03', 'karla.espinoza',     'Administrador del Sistema'),
 (12, '504310985', 'Ana Lucía',  'Gómez',     'Viales',    'Cajera',               '8433-1209', '2021-08-09', 'ana.gomez',          'Administrador del Sistema'),
 (13, '502670438', 'Silvia',     'Morales',   'Contreras', 'Secretaria',           '8805-7716', '2017-04-24', 'silvia.morales',     'Administrador del Sistema'),
 (14, '503940261', 'Mauricio',   'Leal',      'Ordóñez',   'Contador',             '8312-6658', '2018-11-05', 'mauricio.leal',      'Junta Directiva'),
 (15, '502450379', 'Gerardo',    'Carrillo',  'Vallejos',  'Tesorero Junta',       '8851-2093', '2022-05-02', 'gerardo.carrillo',   'Junta Directiva'),
 (16, '503280654', 'Xinia',      'Rosales',   'Obando',    'Secretaria Junta',     '8726-4481', '2022-05-02', 'xinia.rosales',      'Junta Directiva'),
 (17, '504020817', 'Hernán',     'Juárez',    'Gómez',     'Vocal Junta',          '8619-3375', '2022-05-02', 'hernan.juarez',      'Junta Directiva'),
 (18, '502890146', 'Flor',       'Vallejos',  'Ruiz',      'Fiscal Junta',         '8547-9902', '2022-05-02', 'flor.vallejos',      'Junta Directiva'),
 (19, '504750398', 'Andrés',     'Pizarro',   'Leal',      'Técnico en TI',        '8888-1460', '2023-02-13', 'andres.pizarro',     'Administrador de BD'),
 (20, '503620573', 'Luis Diego', 'Mena',      'Briceño',   'Administrador',        '8401-7724', '2016-08-01', 'luis.mena',          'Administrador del Sistema');

CREATE TABLE #con (
    n int NOT NULL PRIMARY KEY, clave varchar(5) NOT NULL,
    id_conexion int NOT NULL, id_medidor int NOT NULL, id_medidor_viejo int NULL);

CREATE TABLE #con_map (n int NOT NULL PRIMARY KEY, clave varchar(5) NOT NULL);
INSERT INTO #con_map (n, clave) VALUES
 (1,'F01'),(2,'F02'),(3,'F03'),(4,'F04'),(5,'F05'),(6,'F06'),(7,'F07'),(8,'F07B'),(9,'F08'),(10,'F09'),
 (11,'F10'),(12,'F11'),(13,'F12'),(14,'F13'),(15,'F14'),(16,'F14B'),(17,'F15'),(18,'F16'),(19,'F17'),(20,'F18'),
 (21,'F19'),(22,'F20'),(23,'F21'),(24,'F22'),(25,'F23'),(26,'F24'),(27,'J01'),(28,'J02'),(29,'J03'),(30,'J04'),
 (31,'J05'),(32,'J06'),(33,'J07'),(34,'J08'),(35,'J09'),(36,'J09B'),(37,'J10'),(38,'J11'),(39,'J12'),(40,'J12B'),
 (41,'J13'),(42,'J14'),(43,'J15'),(44,'J16'),(45,'J17'),(46,'J18'),(47,'J19'),(48,'J20');

INSERT INTO #con (n, clave, id_conexion, id_medidor, id_medidor_viejo)
SELECT map.n, map.clave, act.id_conexion, act.id_medidor, viejo.id_medidor
FROM #con_map map
CROSS APPLY (
    SELECT TOP (1) med.id_medidor, med.id_conexion
    FROM dbo.Medidor med
    WHERE med.numero_serie LIKE CONCAT('SC-', 24000 + map.n, '%') AND med.estado = 'Activo'
    ORDER BY med.numero_serie DESC
) act
OUTER APPLY (
    SELECT TOP (1) med.id_medidor
    FROM dbo.Medidor med
    WHERE map.clave = 'F08' AND med.numero_serie = CONCAT('SC-', 24000 + map.n) AND med.estado = 'Sustituido'
) viejo(id_medidor);
-- Meses con fuga (consumo multiplicado): generan alertas de consumo.
CREATE TABLE #pico (clave varchar(5), mes date, factor decimal(4,2));
INSERT INTO #pico VALUES
 ('F03', '2026-02-01', 3.30), ('J12', '2026-03-01', 2.60), ('F09', '2026-04-01', 3.20),
 ('J05', '2026-06-01', 3.10), ('F12', '2026-08-01', 3.40), ('J13', '2026-09-01', 2.80),
 ('F19', '2026-10-01', 3.30), ('J07', '2026-11-01', 3.50);

-- Incidencias. fontanero = #emp.n (0 = usuario "fontanero" de los datos iniciales).
-- estado_mant: Finalizado, En proceso o Programado; NULL si no hay mantenimiento.
CREATE TABLE #inc (
    n int IDENTITY(1,1) PRIMARY KEY, clave varchar(5), tipo varchar(20), descripcion varchar(100),
    ubicacion varchar(20), fecha datetime, trabajo varchar(15) NULL, fontanero int NULL,
    horas_inicio int NULL, horas_duracion int NULL, inicio_fijo datetime NULL, estado_mant varchar(20) NULL,
    estado_final varchar(20), solucion varchar(400) NULL, id_incidencia int NULL);

INSERT INTO #inc (clave, tipo, descripcion, ubicacion, fecha, trabajo, fontanero, horas_inicio, horas_duracion, inicio_fijo, estado_mant, estado_final, solucion) VALUES
 ('F03', 'Fuga',             'Consumo muy alto; posible fuga en tubería interna',    'Patio trasero',    '2026-02-05 09:30', 'Reparación',     1,  3,  2, NULL, 'Finalizado', 'Resuelta',   'Se reparó un tubo PVC de media pulgada en el patio.'),
 ('J12', 'Fuga',             'Fuga en la línea que alimenta la piscina',             'Área de piscina',  '2026-03-04 08:00', 'Reparación',     3,  4,  6, NULL, 'Finalizado', 'Resuelta',   'Se sustituyó un tramo de tubería de una pulgada.'),
 ('F09', 'Fuga',             'Consumo elevado; posible fuga en servicio sanitario',  'Baño',             '2026-04-06 10:00', 'Reparación',     2, 20,  1, NULL, 'Finalizado', 'Resuelta',   'Se cambió la válvula del tanque del inodoro.'),
 ('J05', 'Fuga',             'Fuga en el tanque del salón comunal',                  'Salón comunal',    '2026-06-07 09:00', 'Reparación',     2, 26,  4, NULL, 'Finalizado', 'Resuelta',   'Se selló la grieta del tanque y se cambió la boya.'),
 ('F12', 'Fuga',             'Lectura muy alta; se sospecha fuga subterránea',       'Acera frontal',    '2026-08-05 08:00', 'Reparación',     5, 24,  5, NULL, 'Finalizado', 'Resuelta',   'Fuga localizada bajo la acera; se reparó y se rellenó la zanja.'),
 ('J13', 'Fuga',             'Fuga en la manguera principal de lavado',              'Zona de lavado',   '2026-09-05 11:00', 'Reparación',     4,  2,  3, NULL, 'Finalizado', 'Resuelta',   'Se cambió la unión y la manguera de alta presión.'),
 ('F19', 'Fuga',             'Fuga en la llave de paso junto al medidor',            'Caja del medidor', '2026-10-07 10:00', 'Reparación',     1,  5,  1, NULL, 'Finalizado', 'Resuelta',   'Se cambió la llave de paso.'),
 ('J07', 'Fuga',             'Consumo anómalo; revisar instalación de la bodega',    'Bodega',           '2026-11-03 14:00', NULL,          NULL, NULL, NULL, NULL, NULL,       'Abierta',    NULL),
 ('F08', 'Medidor dañado',   'Medidor con el visor empañado, no se puede leer',      'Frente a la casa', '2026-06-12 08:15', 'Cambio medidor', 3, 48,  2, NULL, 'Finalizado', 'Resuelta',   'Se sustituyó el medidor por uno nuevo (lectura inicial 0).'),
 ('F01', 'Baja presión',     'Baja presión en horas de la mañana',                   'Cocina',           '2025-12-15 07:40', 'Reparación',     4,  6,  2, NULL, 'Finalizado', 'Resuelta',   'Se limpió el filtro de la entrada.'),
 ('J17', 'Agua turbia',      'Agua con sedimentos en los lavamanos',                 'Baños',            '2025-12-02 09:00', 'Lavado tubería', 5,  4,  3, NULL, 'Finalizado', 'Resuelta',   'Se purgó la tubería; el agua salió clara.'),
 ('F16', 'Tubería rota',     'Tubería rota por trabajos en la calle',                'Calle principal',  '2026-01-19 10:20', 'Reparación',     2,  2,  5, NULL, 'Finalizado', 'Resuelta',   'Se reparó la tubería y se restableció el servicio.'),
 ('J03', 'Sin servicio',     'La escuela amaneció sin agua',                         'Comedor escolar',  '2026-02-24 06:50', 'Reparación',     1,  1,  4, NULL, 'Finalizado', 'Resuelta',   'Se reparó la válvula de la acometida.'),
 ('F05', 'Baja presión',     'Poca presión en la ducha y el tanque',                 'Baño',             '2026-03-20 16:00', 'Reparación',     5, 18,  2, NULL, 'Finalizado', 'Resuelta',   'Se desobstruyó la tubería de entrada.'),
 ('J09', 'Reclamo de cobro', 'Reclama monto alto en la factura de mayo',             'Oficina ASADA',    '2026-05-14 09:00', NULL,          NULL, NULL, NULL, NULL, NULL,       'Resuelta',   'Se revisó la lectura con el abonado; el consumo es correcto.'),
 ('J20', 'Tubería rota',     'Tubería del sistema de riego reventada',               'Vivero',           '2026-07-03 08:00', 'Reparación',     5,  3,  4, NULL, 'Finalizado', 'Resuelta',   'Se cambió el tramo dañado de la línea de riego.'),
 ('J04', 'Conexión ilegal',  'Posible conexión ilegal junto al colegio',             'Lote baldío',      '2026-07-21 09:00', 'Inspección',     1, 26,  2, NULL, 'Finalizado', 'Resuelta',   'Se retiró la conexión ilegal y se notificó a la Junta Directiva.'),
 ('F17', 'Reclamo de cobro', 'Solicita revisar la lectura de agosto',                'Oficina ASADA',    '2026-08-19 10:30', 'Inspección',     4, 24,  1, NULL, 'Finalizado', 'Resuelta',   'Se verificó el medidor en sitio; la lectura es correcta.'),
 ('F22', 'Agua turbia',      'El agua sale turbia después de la lluvia',             'Cocina',           '2026-09-22 17:10', 'Lavado tubería', 3, 15,  3, NULL, 'Finalizado', 'Resuelta',   'Se purgó la línea del sector; el agua salió clara.'),
 ('F24', 'Baja presión',     'Presión baja intermitente por la tarde',               'Patio',            '2026-10-14 15:00', 'Reparación',     6, 17,  2, NULL, 'Finalizado', 'Resuelta',   'Se ajustó la válvula reguladora del sector.'),
 ('J01', 'Sin servicio',     'Sin agua en la soda durante la mañana',                'Cocina',           '2026-10-27 06:30', 'Reparación',     2,  2, NULL, NULL, 'En proceso', 'En proceso', NULL),
 ('F02', 'Medidor dañado',   'El medidor gira sin consumo aparente',                 'Acera',            '2026-10-29 10:00', 'Cambio medidor', 5,  3, NULL, NULL, 'En proceso', 'En proceso', NULL),
 ('F14', 'Tubería rota',     'Tubo PVC roto en la entrada de la casa',               'Entrada',          '2026-10-30 12:00', 'Reparación',     0, NULL, NULL, '2026-11-05 08:00', 'Programado', 'En proceso', NULL),
 ('J06', 'Agua turbia',      'Huéspedes reportan agua con color amarillento',        'Cabina 4',         '2026-11-01 09:00', 'Lavado tubería', 4, NULL, NULL, '2026-11-06 13:00', 'Programado', 'En proceso', NULL),
 ('F10', 'Fuga',             'Charco permanente cerca del medidor',                  'Acera',            '2026-11-02 16:00', NULL,          NULL, NULL, NULL, NULL, NULL,       'Abierta',    NULL),
 ('J11', 'Baja presión',     'Baja presión en la cocina de la panadería',            'Cocina',           '2026-11-03 07:00', NULL,          NULL, NULL, NULL, NULL, NULL,       'Abierta',    NULL),
 ('F18', 'Válvula dañada',   'La válvula de paso no cierra',                         'Caja del medidor', '2026-11-03 11:30', NULL,          NULL, NULL, NULL, NULL, NULL,       'Abierta',    NULL);

-- Mantenimientos sin incidencia (preventivos, instalaciones, cortes).
CREATE TABLE #prev (
    n int IDENTITY(1,1) PRIMARY KEY, clave varchar(5), trabajo varchar(15), descripcion varchar(100),
    inicio datetime, horas int NULL, estado varchar(20), fontanero int, detalle varchar(400) NULL);

INSERT INTO #prev (clave, trabajo, descripcion, inicio, horas, estado, fontanero, detalle) VALUES
 ('J17', 'Preventivo',  'Lavado de tuberías de la guardería',                  '2025-12-13 08:00',  4, 'Finalizado', 5, 'Tuberías lavadas; se recomendó instalar filtro.'),
 ('J03', 'Preventivo',  'Limpieza y desinfección del tanque de la escuela',    '2026-01-10 07:30',  5, 'Finalizado', 1, 'Tanque lavado y clorado; se cambió la boya.'),
 ('J04', 'Preventivo',  'Revisión de válvulas y llaves de paso del colegio',   '2026-02-07 08:00',  4, 'Finalizado', 2, 'Se reemplazaron dos llaves de paso con fuga.'),
 ('J15', 'Preventivo',  'Mantenimiento de llaves en camerinos de la plaza',    '2026-03-14 08:00', NULL, 'Cancelado', 3, 'Cancelado por lluvia; se reprogramará.'),
 ('F05', 'Preventivo',  'Cambio de llave de chorro y revisión de la caja',     '2026-04-18 08:00',  2, 'Finalizado', 6, 'Llave de chorro cambiada; caja del medidor limpia.'),
 ('J12', 'Preventivo',  'Revisión de la red interna del hotel',                '2026-05-16 09:00',  6, 'Finalizado', 3, 'Red en buen estado; se ajustó la presión de entrada.'),
 ('F06', 'Instalación', 'Instalación de nueva conexión y medidor',             '2026-05-20 08:30',  3, 'Finalizado', 4, 'Conexión instalada con medidor nuevo.'),
 ('J18', 'Instalación', 'Instalación de servicio comercial y medidor',         '2026-06-15 08:00',  4, 'Finalizado', 5, 'Servicio comercial instalado con medidor de 3/4.'),
 ('F15', 'Instalación', 'Instalación de nueva conexión',                       '2026-07-08 13:00',  3, 'Finalizado', 6, 'Conexión instalada; se entregó el número de abonado.'),
 ('F20', 'Corte',       'Retiro de medidor por traslado del abonado',          '2026-08-10 09:00',  2, 'Finalizado', 1, 'Medidor retirado y servicio cerrado a solicitud del abonado.'),
 ('J09', 'Preventivo',  'Revisión de presión en la red del supermercado',      '2026-09-12 07:00',  3, 'Finalizado', 2, 'Presión normal; se limpió el filtro de entrada.'),
 ('F23', 'Corte',       'Corte del servicio por morosidad',                    '2026-10-20 09:30',  1, 'Finalizado', 4, 'Servicio cortado; se colocó sello en la llave de paso.'),
 ('J13', 'Preventivo',  'Revisión del sistema de lavado y recirculación',      '2026-11-03 07:30', NULL, 'En proceso', 0, NULL),
 ('J06', 'Preventivo',  'Revisión preventiva de tuberías de las cabinas',      '2026-11-06 08:00', NULL, 'Programado', 0, NULL),
 ('J10', 'Inspección',  'Inspección anual de la instalación',                  '2026-11-09 09:00', NULL, 'Programado', 5, NULL),
 ('J02', 'Inspección',  'Inspección del medidor a solicitud del abonado',      '2026-11-11 10:00', NULL, 'Programado', 6, NULL);

UPDATE e SET id_empleado = emp.id_empleado
FROM #emp e
JOIN dbo.Empleado emp ON emp.cedula = e.cedula;

-- Identificadores existentes antes de la carga (para tocar solo lo nuevo).
CREATE TABLE #limites (tabla varchar(30) PRIMARY KEY, max_id int);
INSERT INTO #limites VALUES
 ('Incidencia',    ISNULL((SELECT MAX(id_incidencia)    FROM dbo.Incidencia), 0)),
 ('Mantenimiento', ISNULL((SELECT MAX(id_mantenimiento) FROM dbo.Mantenimiento), 0)),
 ('Alerta',        ISNULL((SELECT MAX(id_alerta)        FROM dbo.Alerta_Consumo), 0));
GO

SET XACT_ABORT ON;
BEGIN TRANSACTION;

DECLARE @n int, @id int, @clave varchar(5), @tipo varchar(10), @c int, @m int,
        @tipo_inc int, @desc varchar(100), @ubi varchar(20), @fecha_inc datetime, @trabajo int, @emp int,
        @ini datetime, @fin_m datetime, @estado_m varchar(20), @estado_f varchar(20), @sol varchar(400),
        @id_alerta int, @id_inc int, @id_mant int, @fontanero_base int, @horas_i int, @horas_d int, @ini_fijo datetime;

PRINT 'Incidencias y mantenimientos...';
SELECT @fontanero_base = id_empleado FROM dbo.Empleado WHERE cedula = '100000003';

SET @n = 1;
WHILE @n <= (SELECT MAX(n) FROM #inc)
BEGIN
    SELECT @clave = i.clave, @tipo_inc = ti.id_tipo_incidencia, @desc = i.descripcion, @ubi = i.ubicacion,
           @fecha_inc = i.fecha, @trabajo = tt.id_tipo_trabajo,
           @emp = CASE WHEN i.fontanero = 0 THEN @fontanero_base ELSE e.id_empleado END,
           @horas_i = i.horas_inicio, @horas_d = i.horas_duracion, @ini_fijo = i.inicio_fijo,
           @estado_m = i.estado_mant, @estado_f = i.estado_final, @sol = i.solucion,
           @m = CASE WHEN i.clave = 'F08' THEN c.id_medidor_viejo ELSE c.id_medidor END
    FROM #inc i
    JOIN #con c ON c.clave = i.clave
    JOIN dbo.Tipo_Incidencia ti ON ti.nombre_incidencia = i.tipo
    LEFT JOIN dbo.Tipo_Trabajo tt ON tt.nombre_trabajo = i.trabajo
    LEFT JOIN #emp e ON e.n = i.fontanero
    WHERE i.n = @n;

    -- Las fugas se reportan a partir de la alerta de consumo de la lectura de ese mes.
    SET @id_alerta = NULL;
    IF EXISTS (SELECT 1 FROM #pico WHERE clave = @clave AND mes = DATEFROMPARTS(YEAR(@fecha_inc), MONTH(@fecha_inc), 1))
    BEGIN
        SELECT TOP (1) @id_alerta = a.id_alerta, @fecha_inc = DATEADD(HOUR, 26, l.fecha_lectura_actual)
        FROM dbo.Alerta_Consumo a JOIN dbo.Lectura l ON l.id_lectura = a.id_lectura
        WHERE l.id_medidor = @m AND a.id_incidencia IS NULL
          AND l.fecha_lectura_actual >= DATEFROMPARTS(YEAR(@fecha_inc), MONTH(@fecha_inc), 1)
        ORDER BY l.fecha_lectura_actual DESC;
        IF @fecha_inc > GETDATE() SET @fecha_inc = DATEADD(HOUR, -6, GETDATE());
    END

    EXEC dbo.sp_RegistrarIncidente @id_medidor = @m, @id_tipo_incidencia = @tipo_inc, @descripcion = @desc,
         @ubicacion = @ubi, @fecha_incidente = @fecha_inc, @id_alerta = @id_alerta, @id_incidencia = @id_inc OUTPUT;
    UPDATE #inc SET id_incidencia = @id_inc WHERE n = @n;

    IF @trabajo IS NOT NULL
    BEGIN
        SET @ini = ISNULL(@ini_fijo, DATEADD(HOUR, @horas_i, @fecha_inc));
        EXEC dbo.sp_AsignarMantenimiento @id_incidencia = @id_inc, @id_empleado = @emp, @id_tipo_trabajo = @trabajo,
             @fecha_inicio = @ini, @id_mantenimiento = @id_mant OUTPUT;

        IF @estado_m = 'Finalizado'
        BEGIN
            SET @fin_m = DATEADD(HOUR, @horas_d, @ini);
            EXEC dbo.sp_CerrarMantenimiento @id_mantenimiento = @id_mant, @detalle = @sol, @fecha_fin = @fin_m;
            IF @id_alerta IS NOT NULL
                UPDATE dbo.Alerta_Consumo
                SET estado = 'Resuelta', fecha_resolucion = CAST(@fin_m AS date), observacion = CONCAT('Fuga atendida: ', @sol)
                WHERE id_alerta = @id_alerta;
        END
        ELSE IF @estado_m = 'En proceso'
            EXEC dbo.sp_CambiarEstadoMantenimiento @id_mantenimiento = @id_mant, @nuevo_estado = 'En proceso',
                 @anotacion = 'El fontanero está trabajando en el sitio.';
    END
    ELSE IF @estado_f = 'Resuelta'
    BEGIN
        EXEC dbo.sp_CambiarEstadoIncidencia @id_incidencia = @id_inc, @nuevo_estado = 'En proceso',
             @observacion = 'Se revisa el caso en la oficina.';
        EXEC dbo.sp_CerrarIncidente @id_incidencia = @id_inc, @solucion = @sol;
    END
    SET @n += 1;
END

SET @n = 1;
WHILE @n <= (SELECT MAX(n) FROM #prev)
BEGIN
    SELECT @c = c.id_conexion, @trabajo = tt.id_tipo_trabajo, @desc = p.descripcion, @ini = p.inicio,
           @horas_d = p.horas, @estado_m = p.estado, @sol = p.detalle,
           @emp = CASE WHEN p.fontanero = 0 THEN @fontanero_base ELSE e.id_empleado END
    FROM #prev p
    JOIN #con c ON c.clave = p.clave
    JOIN dbo.Tipo_Trabajo tt ON tt.nombre_trabajo = p.trabajo
    LEFT JOIN #emp e ON e.n = p.fontanero
    WHERE p.n = @n;

    EXEC dbo.sp_ProgramarMantenimiento @id_empleado = @emp, @id_tipo_trabajo = @trabajo, @id_conexion = @c,
         @descripcion = @desc, @fecha_inicio = @ini, @id_mantenimiento = @id_mant OUTPUT;

    IF @estado_m = 'Finalizado'
    BEGIN
        SET @fin_m = DATEADD(HOUR, @horas_d, @ini);
        EXEC dbo.sp_CerrarMantenimiento @id_mantenimiento = @id_mant, @detalle = @sol, @fecha_fin = @fin_m;
    END
    ELSE IF @estado_m IN ('En proceso', 'Cancelado')
        EXEC dbo.sp_CambiarEstadoMantenimiento @id_mantenimiento = @id_mant, @nuevo_estado = @estado_m,
             @anotacion = @sol;
    SET @n += 1;
END

PRINT 'Corrigiendo fechas del historial...';
DECLARE @max_inc int = (SELECT max_id FROM #limites WHERE tabla = 'Incidencia'),
        @max_mant int = (SELECT max_id FROM #limites WHERE tabla = 'Mantenimiento'),
        @max_alerta int = (SELECT max_id FROM #limites WHERE tabla = 'Alerta');

-- Un mantenimiento cancelado se cierra el mismo día programado.
UPDATE dbo.Mantenimiento SET fecha_fin = fecha_inicio
WHERE id_mantenimiento > @max_mant AND estado = 'Cancelado';

UPDATE h SET fecha_evento = CASE
        WHEN h.estado_anterior IS NULL THEN
             CASE WHEN m.id_incidencia IS NOT NULL THEN DATEADD(MINUTE, 50, i.fecha_incidente)
                  WHEN DATEADD(DAY, -4, m.fecha_inicio) < GETDATE() THEN DATEADD(DAY, -4, m.fecha_inicio)
                  ELSE DATEADD(HOUR, -30, GETDATE()) END
        WHEN h.estado_actual = 'En proceso' THEN m.fecha_inicio
        ELSE m.fecha_fin END
FROM dbo.Historial_Mantenimiento h
JOIN dbo.Mantenimiento m ON m.id_mantenimiento = h.id_mantenimiento
LEFT JOIN dbo.Incidencia i ON i.id_incidencia = m.id_incidencia
WHERE m.id_mantenimiento > @max_mant;

UPDATE h SET fecha_evento = CASE
        WHEN h.estado_anterior IS NULL       THEN i.fecha_incidente
        WHEN h.estado_actual = 'En proceso'  THEN DATEADD(MINUTE, 50, i.fecha_incidente)
        ELSE COALESCE(x.fin, DATEADD(HOUR, 30, i.fecha_incidente)) END
FROM dbo.Historial_Incidencia h
JOIN dbo.Incidencia i ON i.id_incidencia = h.id_incidencia
OUTER APPLY (SELECT MAX(fecha_fin) AS fin FROM dbo.Mantenimiento WHERE id_incidencia = i.id_incidencia) x
WHERE i.id_incidencia > @max_inc;

UPDATE i SET fecha_modificacion = x.ultimo
FROM dbo.Incidencia i
CROSS APPLY (SELECT MAX(fecha_evento) AS ultimo FROM dbo.Historial_Incidencia WHERE id_incidencia = i.id_incidencia) x
WHERE i.id_incidencia > @max_inc;

UPDATE m SET fecha_modificacion = x.ultimo
FROM dbo.Mantenimiento m
CROSS APPLY (SELECT MAX(fecha_evento) AS ultimo FROM dbo.Historial_Mantenimiento WHERE id_mantenimiento = m.id_mantenimiento) x
WHERE m.id_mantenimiento > @max_mant;

-- Las alertas se detectan el día de la lectura. Las que no terminaron en una
-- fuga (picos de verano) se revisaron con el abonado una semana después.
UPDATE a SET fecha_deteccion = CAST(l.fecha_lectura_actual AS date)
FROM dbo.Alerta_Consumo a JOIN dbo.Lectura l ON l.id_lectura = a.id_lectura
WHERE a.id_alerta > @max_alerta;

UPDATE dbo.Alerta_Consumo
SET fecha_deteccion = CASE WHEN fecha_resolucion < fecha_deteccion THEN fecha_resolucion ELSE fecha_deteccion END
WHERE id_alerta > @max_alerta AND estado = 'Resuelta';

UPDATE dbo.Alerta_Consumo
SET estado = 'Resuelta', fecha_resolucion = DATEADD(DAY, 7, fecha_deteccion),
    observacion = 'Se revisó con el abonado: aumento por temporada seca, sin fuga.'
WHERE id_alerta > @max_alerta AND estado = 'Abierta' AND id_incidencia IS NULL
  AND fecha_deteccion < DATEADD(DAY, -30, GETDATE());
COMMIT;
PRINT 'Incidencias y mantenimientos demo cargados.';
GO

EXEC dbo.sp_ETL_CargaIncidenciasDW @desde = '19000101';
EXEC dbo.sp_ETL_CargaMantenimientosDW @desde = '19000101';
EXEC dbo.sp_ValidarCargaDW;
GO

