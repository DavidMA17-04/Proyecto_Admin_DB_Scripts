SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
/* ---------------------------------------------------------------------
   Script 19: Datos de demostración

   Simula un año de operación de la ASADA (noviembre 2025 a noviembre 2026)
   para que el sistema, los reportes y el Data Warehouse tengan datos:
     - 20 empleados y 18 usuarios del sistema
     - 24 abonados físicos y 20 jurídicos, con 48 conexiones y medidores
     - lecturas mensuales, facturas, pagos, recargos por mora y prórrogas
     - 26 incidencias, 38 mantenimientos y alertas de consumo
     - un aumento de tarifas en junio 2026 (Historial_Tarifa)
     - respaldos reales y la carga completa del Data Warehouse

   Todo se registra con los procedimientos del sistema (validaciones,
   triggers y bitácora). Después se corren las fechas hacia atrás para
   simular el historial, igual que sp_CargarDatosPrueba.

   Se ejecuta una sola vez, con el usuario admin de la aplicación como autor:
       sqlcmd -S localhost -E -C -f 65001 -i 19_datos_demo.sql
   Los medidores de la demo tienen número de serie 'SC-…' y los correos
   terminan en '@demo.cr'.
   --------------------------------------------------------------------- */
USE ASADA;
GO
SET NOCOUNT ON;
GO

IF EXISTS (SELECT 1 FROM dbo.Medidor WHERE numero_serie LIKE 'SC-%')
BEGIN
    RAISERROR('Los datos de demostración ya están cargados (medidores SC-). No se cargó nada.', 16, 1);
    SET NOEXEC ON;
END
GO

-- La bitácora queda a nombre del usuario admin.
DECLARE @admin int, @emp_admin int;
SELECT @admin = id_usuario_sistema, @emp_admin = id_empleado FROM dbo.Usuario_Sistema WHERE nombre_usuario = 'admin';
EXEC sys.sp_set_session_context @key = N'id_usuario_sistema', @value = @admin;
EXEC sys.sp_set_session_context @key = N'id_empleado', @value = @emp_admin;
GO

   --Respaldo completo antes de cargar (punto de retorno)
PRINT 'Respaldo completo previo...';
DECLARE @politica int;
SELECT @politica = p.id_politica FROM dbo.Politica_Respaldo p
JOIN dbo.Tipo_Respaldo t ON t.id_tipo_respaldo = p.id_tipo_respaldo
WHERE t.nombre_respaldo = 'Completo' AND p.activo = 1;
EXEC dbo.sp_EjecutarRespaldo @id_politica = @politica;
GO

   --Datos fuente
IF OBJECT_ID('tempdb..#emp') IS NOT NULL DROP TABLE #emp;
IF OBJECT_ID('tempdb..#ab')  IS NOT NULL DROP TABLE #ab;
IF OBJECT_ID('tempdb..#con') IS NOT NULL DROP TABLE #con;
IF OBJECT_ID('tempdb..#pico') IS NOT NULL DROP TABLE #pico;
IF OBJECT_ID('tempdb..#inc') IS NOT NULL DROP TABLE #inc;
IF OBJECT_ID('tempdb..#prev') IS NOT NULL DROP TABLE #prev;
IF OBJECT_ID('tempdb..#limites') IS NOT NULL DROP TABLE #limites;

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

CREATE TABLE #ab (
    clave varchar(5) PRIMARY KEY, tipo_id varchar(20), ident varchar(20), nombre varchar(50),
    ap1 varchar(50) NULL, ap2 varchar(50) NULL, nac date NULL, direccion varchar(200), tel varchar(20) NULL,
    correo varchar(100) NULL, rep_ced varchar(20) NULL, rep_nom varchar(50) NULL, rep_ap1 varchar(50) NULL,
    rep_ap2 varchar(50) NULL, registro date, id_abonado int NULL, tipo_abonado varchar(10) NULL);

INSERT INTO #ab (clave, tipo_id, ident, nombre, ap1, ap2, nac, direccion, tel, correo, registro) VALUES
 ('F01', 'FISICA',    '501230987',    'Rosa',          'Gutiérrez',  'Matarrita', '1956-04-12', 'Santa Cruz, Barrio Los Ángeles, 100 m sur de la iglesia',       '8845-1290', 'rosa.gutierrez@demo.cr',     '2015-03-10'),
 ('F02', 'FISICA',    '502340118',    'Carlos',        'Alvarado',   'Rosales',   '1978-09-03', 'Santa Cruz, Barrio Buenos Aires, 50 m este del parque',         '8723-4410', 'carlos.alvarado@demo.cr',    '2017-06-22'),
 ('F03', 'FISICA',    '503450229',    'María José',    'Pizarro',    'Leal',      '1985-12-21', 'Santa Cruz, Barrio Corobicí, casa esquinera color verde',       '8634-9081', 'mariajose.pizarro@demo.cr',  '2018-02-14'),
 ('F04', 'FISICA',    '504560330',    'José Pablo',    'Chaves',     'Obando',    '1990-02-14', 'Santa Cruz, Barrio Limón, 200 m norte del EBAIS',              '8590-3372', NULL,                         '2019-08-05'),
 ('F05', 'FISICA',    '501670441',    'Ana Cecilia',   'Carrillo',   'Baltodano', '1962-07-30', 'Santa Cruz, Barrio San Martín, frente a la plaza',             '2680-1147', 'ana.carrillo@demo.cr',       '2012-11-19'),
 ('F06', 'FISICA',    '505780552',    'Luis Fernando', 'Villalobos', 'Cortés',    '1999-05-08', 'Santa Cruz, Urbanización Las Tejas, lote 18',                  '8411-6025', 'luisfer.villalobos@demo.cr', '2026-05-12'),
 ('F07', 'FISICA',    '502890663',    'Marta Eugenia', 'Rodríguez',  'Juárez',    '1971-11-17', 'Santa Cruz, Barrio Chorotega, 75 m oeste de la pulpería',      '8867-2290', 'marta.rodriguez@demo.cr',    '2014-04-03'),
 ('F08', 'FISICA',    '503910774',    'Juan Carlos',   'Espinoza',   'Gómez',     '1983-03-25', 'Santa Cruz, Barrio Guayacán, casa 7',                          '8702-5518', NULL,                         '2016-09-28'),
 ('F09', 'FISICA',    '504020885',    'Sofía',         'Mena',       'Vallejos',  '1995-08-19', 'Santa Cruz, Lomas del Sur, casa 23',                           '8355-1406', 'sofia.mena@demo.cr',         '2021-01-11'),
 ('F10', 'FISICA',    '501130996',    'Rodolfo',       'Contreras',  'Dinarte',   '1958-01-06', 'Santa Cruz, Barrio Los Ángeles, contiguo al taller',           '2680-3359', NULL,                         '2010-05-17'),
 ('F11', 'DIMEX',     '155812345678', 'Francisco',     'López',      'Martínez',  '1980-06-11', 'Santa Cruz, Barrio Limón, cuarterías Don Beto número 3',       '8476-0921', NULL,                         '2020-10-06'),
 ('F12', 'FISICA',    '503240107',    'Laura',         'Viales',     'Chavarría', '1988-10-02', 'Santa Cruz, Barrio Buenos Aires, casa 41',                     '8819-7734', 'laura.viales@demo.cr',       '2019-03-27'),
 ('F13', 'FISICA',    '504350218',    'Diego',         'Ordóñez',    'Angulo',    '1992-04-27', 'Santa Cruz, Barrio Corobicí, 25 m sur del supermercado',       '8540-2268', 'diego.ordonez@demo.cr',      '2020-07-15'),
 ('F14', 'FISICA',    '502460329',    'Patricia',      'Leal',       'Villegas',  '1975-12-09', 'Santa Cruz, Barrio San Martín, casa 9',                        '8693-1185', 'patricia.leal@demo.cr',      '2013-08-21'),
 ('F15', 'FISICA',    '505570430',    'Kevin',         'Matarrita',  'Ruiz',      '2001-07-15', 'Santa Cruz, Urbanización Las Tejas, lote 33',                  '8305-4472', 'kevin.matarrita@demo.cr',    '2026-07-01'),
 ('F16', 'FISICA',    '501680541',    'Olga',          'Briceño',    'Cubillo',   '1950-03-03', 'Santa Cruz, Barrio Chorotega, casa de madera frente al río',   '2680-5521', NULL,                         '2008-01-30'),
 ('F17', 'FISICA',    '503790652',    'Fabián',        'Gómez',      'Lara',      '1986-09-28', 'Santa Cruz, Barrio Guayacán, casa 15',                         '8758-6643', 'fabian.gomez@demo.cr',       '2018-12-04'),
 ('F18', 'DIMEX',     '155823456789', 'Reyna',         'Hernández',  'Sánchez',   '1977-01-19', 'Santa Cruz, Barrio Limón, 300 m este de la escuela',           '8521-3307', NULL,                         '2022-03-09'),
 ('F19', 'FISICA',    '504810763',    'Andrea',        'Cubillo',    'Morales',   '1993-05-05', 'Santa Cruz, Lomas del Sur, casa 8',                            '8842-0198', 'andrea.cubillo@demo.cr',     '2021-09-20'),
 ('F20', 'FISICA',    '502920874',    'Gilberto',      'Rosales',    'Pizarro',   '1968-08-22', 'Santa Cruz, Barrio Los Ángeles, casa 30',                      '8617-9952', NULL,                         '2011-06-13'),
 ('F21', 'PASAPORTE', 'B7731942',     'Thomas',        'Miller',     NULL,        '1965-02-11', 'Santa Cruz, Barrio San Martín, casa blanca con portón negro',  '8398-2716', 'thomas.miller@demo.cr',      '2023-04-18'),
 ('F22', 'FISICA',    '503030985',    'Jessica',       'Alvarado',   'Mena',      '1997-11-30', 'Santa Cruz, Barrio Buenos Aires, casa 12',                     '8724-5539', 'jessica.alvarado@demo.cr',   '2022-11-02'),
 ('F23', 'FISICA',    '504140196',    'Marvin',        'Obando',     'Carrillo',  '1981-06-16', 'Santa Cruz, Barrio Corobicí, casa 5',                          '8566-8810', NULL,                         '2017-02-08'),
 ('F24', 'FISICA',    '501250207',    'Isabel',        'Juárez',     'Espinoza',  '1960-10-04', 'Santa Cruz, Barrio Chorotega, 100 m norte del salón comunal',  '2680-7743', 'isabel.juarez@demo.cr',      '2009-10-26');

INSERT INTO #ab (clave, tipo_id, ident, nombre, direccion, tel, correo, rep_ced, rep_nom, rep_ap1, rep_ap2, registro) VALUES
 ('J01', 'JURIDICA', '3101456789', 'Soda y Restaurante El Sabanero S.A.',            'Santa Cruz, Barrio Los Ángeles, frente a la terminal de buses', '2680-4411', 'sodaelsabanero@demo.cr',       '503112233', 'Hilda',     'Matarrita', 'Leal',     '2014-07-01'),
 ('J02', 'JURIDICA', '3101567890', 'Pulpería y Abastecedor La Esquina S.A.',         'Santa Cruz, Barrio Limón, esquina noreste de la plaza',          '2680-2290', NULL,                           '504223344', 'Ronald',    'Chavarría', 'Gómez',    '2012-03-15'),
 ('J03', 'JURIDICA', '3008123456', 'Junta de Educación Escuela Los Guayacanes',      'Santa Cruz, Barrio Guayacán, 200 m oeste del templo',            '2680-0130', 'esc.losguayacanes@demo.cr',    '502334455', 'Mireya',    'Pizarro',   'Rosales',  '2005-02-01'),
 ('J04', 'JURIDICA', '3008234567', 'Junta Administrativa Colegio Chorotega',         'Santa Cruz, Barrio Chorotega, carretera a Diriá',               '2680-0255', 'colegio.chorotega@demo.cr',    '503445566', 'Álvaro',    'Contreras', 'Juárez',   '2006-01-20'),
 ('J05', 'JURIDICA', '3002345678', 'Asociación de Desarrollo Integral Barrio Limón', 'Santa Cruz, Barrio Limón, salón comunal',                        '2680-6618', 'adi.barriolimon@demo.cr',      '501556677', 'Teresa',    'Ruiz',      'Cubillo',  '2010-09-09'),
 ('J06', 'JURIDICA', '3101678901', 'Cabinas Brisas del Diriá S.A.',                  'Santa Cruz, salida a Santa Bárbara, 1 km al este',               '2680-8890', 'brisasdiria@demo.cr',          '504667788', 'Esteban',   'Rosales',   'Mena',     '2016-05-23'),
 ('J07', 'JURIDICA', '3101789012', 'Ferretería El Constructor S.A.',                 'Santa Cruz, Barrio San Martín, 50 m sur del banco',              '2680-3021', 'ferreconstructor@demo.cr',     '503778899', 'Wálter',    'Gómez',     'Briceño',  '2015-10-12'),
 ('J08', 'JURIDICA', '3102890123', 'Taller Mecánico Hermanos Gómez Ltda.',           'Santa Cruz, Barrio Corobicí, contiguo a la bomba',               '2680-5577', NULL,                           '502889900', 'Rigoberto', 'Gómez',     'Angulo',   '2013-04-08'),
 ('J09', 'JURIDICA', '3101901234', 'Supermercado La Económica S.A.',                 'Santa Cruz, centro, costado norte del parque',                   '2680-1000', 'superlaeconomica@demo.cr',     '504990011', 'Mario',     'Leal',      'Viales',   '2011-12-01'),
 ('J10', 'JURIDICA', '3002012345', 'Iglesia Evangélica Camino de Fe',                'Santa Cruz, Barrio Buenos Aires, 100 m norte de la escuela',     '2680-9134', NULL,                           '503101122', 'Samuel',    'Ordóñez',   'Pizarro',  '2017-08-14'),
 ('J11', 'JURIDICA', '3101123450', 'Panadería y Repostería Doña Tina S.A.',          'Santa Cruz, Barrio Los Ángeles, 25 m este del correo',           '2680-2745', 'panaderiadonatina@demo.cr',    '501212233', 'Cristina',  'Vallejos',  'Carrillo', '2014-01-27'),
 ('J12', 'JURIDICA', '3101234561', 'Hotel Sol de Guanacaste S.A.',                   'Santa Cruz, carretera a Tamarindo, 800 m oeste',                 '2680-7000', 'hotelsoldeguanacaste@demo.cr', '504323344', 'Gabriela',  'Angulo',    'Morales',  '2018-06-04'),
 ('J13', 'JURIDICA', '3102345672', 'Lavacar Express Chorotega Ltda.',                'Santa Cruz, Barrio Chorotega, frente al estadio',                '2680-6402', NULL,                           '505434455', 'Bryan',     'Villegas',  'Lara',     '2020-02-17'),
 ('J14', 'JURIDICA', '3101456783', 'Farmacia Santa Cruz Salud S.A.',                 'Santa Cruz, centro, 50 m oeste del hospital',                    '2680-3388', 'farmaciascsalud@demo.cr',      '503545566', 'Daniela',   'Cortés',    'Obando',   '2019-11-11'),
 ('J15', 'JURIDICA', '3002567894', 'Asociación Deportiva Barrio San Martín',         'Santa Cruz, Barrio San Martín, plaza de deportes',               '2680-4720', NULL,                           '502656677', 'Henry',     'Espinoza',  'Dinarte',  '2012-07-19'),
 ('J16', 'JURIDICA', '3101678905', 'Carnicería El Novillo S.A.',                     'Santa Cruz, mercado municipal, local 6',                         '2680-2193', NULL,                           '504767788', 'Óscar',     'Baltodano', 'Ruiz',     '2016-03-02'),
 ('J17', 'JURIDICA', '3007789016', 'Guardería Infantil Pasitos Felices',             'Santa Cruz, Lomas del Sur, casa 2',                              '2680-9561', 'pasitosfelices@demo.cr',       '503878899', 'Karen',     'Mena',      'Chaves',   '2021-05-10'),
 ('J18', 'JURIDICA', '3101890127', 'Restaurante Mariscos La Bahía S.A.',             'Santa Cruz, centro, 100 m sur de la Municipalidad',              '2680-8125', 'mariscoslabahia@demo.cr',      '505989900', 'Alonso',    'Cubillo',   'Leal',     '2026-06-08'),
 ('J19', 'JURIDICA', '3101901238', 'Heladería Coco Frío S.A.',                       'Santa Cruz, Barrio Buenos Aires, frente al parque',              '2680-1567', NULL,                           '504090011', 'Paola',     'Juárez',    'Viales',   '2019-04-01'),
 ('J20', 'JURIDICA', '3102012349', 'Vivero y Jardinería El Guanacaste Ltda.',        'Santa Cruz, salida a Diriá, 500 m sur del puente',              '2680-7319', 'viveroelguanacaste@demo.cr',   '502101123', 'Ernesto',   'Lara',      'Rosales',  '2015-09-15');

-- Conexiones. perfil de pago: P puntual, T paga tarde, A paga en abonos,
-- M deja de pagar desde "corte", N conexión nueva, I se da de baja en "fin".
-- base: consumo promedio en m³; dia: día del mes en que se lee el medidor.
CREATE TABLE #con (
    n int IDENTITY(1,1) PRIMARY KEY, clave varchar(5) UNIQUE, abonado varchar(5), ubicacion varchar(50),
    tarifa varchar(15), desde date, base decimal(10,2), perfil char(1), corte date NULL, fin date NULL, dia int,
    id_conexion int NULL, id_medidor int NULL, id_medidor_viejo int NULL);

INSERT INTO #con (clave, abonado, ubicacion, tarifa, desde, base, perfil, corte, fin, dia) VALUES
 ('F01',  'F01', 'B. Los Ángeles, 100 m sur de la iglesia',  'Preferencial',  '2015-03-10',  10, 'P', NULL, NULL, 2),
 ('F02',  'F02', 'B. Buenos Aires, 50 m este del parque',    'Residencial',   '2017-06-22',  22, 'T', NULL, NULL, 3),
 ('F03',  'F03', 'B. Corobicí, casa esquinera verde',        'Residencial',   '2018-02-14',  18, 'P', NULL, NULL, 4),
 ('F04',  'F04', 'B. Limón, 200 m norte del EBAIS',          'Residencial',   '2019-08-05',  20, 'M', '2026-06-01', NULL, 5),
 ('F05',  'F05', 'B. San Martín, frente a la plaza',         'Preferencial',  '2012-11-19',  11, 'P', NULL, NULL, 2),
 ('F06',  'F06', 'Urb. Las Tejas, lote 18',                  'Residencial',   '2026-05-20',  16, 'N', NULL, NULL, 3),
 ('F07',  'F07', 'B. Chorotega, 75 m oeste de la pulpería',  'Residencial',   '2014-04-03',  24, 'P', NULL, NULL, 6),
 ('F07B', 'F07', 'B. Chorotega, cabinas Doña Marta',         'Comercial',     '2019-01-15',  38, 'P', NULL, NULL, 6),
 ('F08',  'F08', 'B. Guayacán, casa 7',                      'Residencial',   '2016-09-28',  19, 'A', NULL, NULL, 4),
 ('F09',  'F09', 'Lomas del Sur, casa 23',                   'Residencial',   '2021-01-11',  15, 'P', NULL, NULL, 5),
 ('F10',  'F10', 'B. Los Ángeles, contiguo al taller',       'Preferencial',  '2010-05-17',   9, 'T', NULL, NULL, 2),
 ('F11',  'F11', 'B. Limón, cuarterías Don Beto 3',          'Residencial',   '2020-10-06',  14, 'P', NULL, NULL, 3),
 ('F12',  'F12', 'B. Buenos Aires, casa 41',                 'Residencial',   '2019-03-27',  21, 'P', NULL, NULL, 4),
 ('F13',  'F13', 'B. Corobicí, 25 m sur del supermercado',   'Residencial',   '2020-07-15',  17, 'M', '2026-07-01', NULL, 5),
 ('F14',  'F14', 'B. San Martín, casa 9',                    'Residencial',   '2013-08-21',  23, 'P', NULL, NULL, 6),
 ('F14B', 'F14', 'B. San Martín, casa de alquiler 9A',       'Residencial',   '2020-03-01',  15, 'T', NULL, NULL, 6),
 ('F15',  'F15', 'Urb. Las Tejas, lote 33',                  'Residencial',   '2026-07-08',  13, 'N', NULL, NULL, 2),
 ('F16',  'F16', 'B. Chorotega, casa frente al río',         'Preferencial',  '2008-01-30',   8, 'P', NULL, NULL, 3),
 ('F17',  'F17', 'B. Guayacán, casa 15',                     'Residencial',   '2018-12-04',  20, 'T', NULL, NULL, 4),
 ('F18',  'F18', 'B. Limón, 300 m este de la escuela',       'Residencial',   '2022-03-09',  18, 'A', NULL, NULL, 5),
 ('F19',  'F19', 'Lomas del Sur, casa 8',                    'Residencial',   '2021-09-20',  16, 'P', NULL, NULL, 6),
 ('F20',  'F20', 'B. Los Ángeles, casa 30',                  'Residencial',   '2011-06-13',  19, 'I', NULL, '2026-07-01', 2),
 ('F21',  'F21', 'B. San Martín, casa con portón negro',     'Residencial',   '2023-04-18',  26, 'P', NULL, NULL, 3),
 ('F22',  'F22', 'B. Buenos Aires, casa 12',                 'Residencial',   '2022-11-02',  17, 'P', NULL, NULL, 4),
 ('F23',  'F23', 'B. Corobicí, casa 5',                      'Residencial',   '2017-02-08',  21, 'M', '2026-05-01', NULL, 5),
 ('F24',  'F24', 'B. Chorotega, 100 m norte del salón',      'Preferencial',  '2009-10-26',  10, 'P', NULL, NULL, 6),
 ('J01',  'J01', 'B. Los Ángeles, Soda El Sabanero',    'Comercial',     '2014-07-01',  48, 'P', NULL, NULL, 2),
 ('J02',  'J02', 'B. Limón, esquina noreste de la plaza',    'Comercial',     '2012-03-15',  26, 'T', NULL, NULL, 3),
 ('J03',  'J03', 'B. Guayacán, Escuela Los Guayacanes', 'Institucional', '2005-02-01', 115, 'P', NULL, NULL, 4),
 ('J04',  'J04', 'B. Chorotega, Colegio Chorotega', 'Institucional', '2006-01-20', 140, 'P', NULL, NULL, 5),
 ('J05',  'J05', 'B. Limón, Salón comunal',    'Institucional', '2010-09-09',  30, 'A', NULL, NULL, 6),
 ('J06',  'J06', 'Salida a Santa Bárbara, Cabinas Brisas del Diriá', 'Comercial',     '2016-05-23',  72, 'P', NULL, NULL, 2),
 ('J07',  'J07', 'B. San Martín, Ferretería El Constructor', 'Comercial',     '2015-10-12',  18, 'P', NULL, NULL, 3),
 ('J08',  'J08', 'B. Corobicí, Taller Mecánico Hermanos Gómez', 'Comercial',     '2013-04-08',  30, 'M', '2026-08-01', NULL, 4),
 ('J09',  'J09', 'Centro, Supermercado La Económica', 'Comercial',     '2011-12-01',  62, 'P', NULL, NULL, 5),
 ('J09B', 'J09', 'Centro, Bodega del Supermercado La Económica', 'Comercial',     '2018-08-20',  14, 'P', NULL, NULL, 5),
 ('J10',  'J10', 'B. Buenos Aires, Iglesia Camino de Fe', 'Institucional', '2017-08-14',  20, 'P', NULL, NULL, 6),
 ('J11',  'J11', 'B. Los Ángeles, Panadería Doña Tina', 'Comercial',     '2014-01-27',  36, 'T', NULL, NULL, 2),
 ('J12',  'J12', 'Carretera a Tamarindo, Hotel Sol de Guanacaste', 'Comercial',     '2018-06-04', 180, 'P', NULL, NULL, 3),
 ('J12B', 'J12', 'Carretera a Tamarindo, Hotel Sol, área social', 'Comercial',     '2021-11-15',  85, 'P', NULL, NULL, 3),
 ('J13',  'J13', 'B. Chorotega, Lavacar Express Chorotega', 'Comercial',     '2020-02-17', 150, 'A', NULL, NULL, 4),
 ('J14',  'J14', 'Centro, Farmacia Santa Cruz Salud', 'Comercial',     '2019-11-11',  12, 'P', NULL, NULL, 5),
 ('J15',  'J15', 'B. San Martín, Plaza de deportes', 'Institucional', '2012-07-19',  58, 'P', NULL, NULL, 6),
 ('J16',  'J16', 'Centro, Mercado municipal, local 6', 'Comercial',     '2016-03-02',  40, 'M', '2026-07-01', NULL, 2),
 ('J17',  'J17', 'Lomas del Sur, Guardería Pasitos Felices', 'Institucional', '2021-05-10',  34, 'P', NULL, NULL, 3),
 ('J18',  'J18', 'Centro, Restaurante Mariscos La Bahía', 'Comercial',     '2026-06-15',  78, 'N', NULL, NULL, 4),
 ('J19',  'J19', 'B. Buenos Aires, Heladería Coco Frío', 'Comercial',     '2019-04-01',  22, 'P', NULL, NULL, 5),
 ('J20',  'J20', 'Salida a Diriá, Vivero El Guanacaste', 'Comercial',     '2015-09-15',  95, 'T', NULL, NULL, 6);

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

-- Identificadores existentes antes de la carga (para tocar solo lo nuevo).
CREATE TABLE #limites (tabla varchar(30) PRIMARY KEY, max_id int);
INSERT INTO #limites VALUES
 ('Incidencia',    ISNULL((SELECT MAX(id_incidencia)    FROM dbo.Incidencia), 0)),
 ('Mantenimiento', ISNULL((SELECT MAX(id_mantenimiento) FROM dbo.Mantenimiento), 0)),
 ('Alerta',        ISNULL((SELECT MAX(id_alerta)        FROM dbo.Alerta_Consumo), 0));
GO

   --Carga principal (una sola transacción)
SET XACT_ABORT ON;
BEGIN TRANSACTION;

PRINT 'Catálogos y tarifas...';
INSERT INTO dbo.Tipo_Incidencia (nombre_incidencia)
SELECT v.n FROM (VALUES ('Válvula dañada'), ('Conexión ilegal'), ('Hidrante dañado')) v(n)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Tipo_Incidencia t WHERE t.nombre_incidencia = v.n);

INSERT INTO dbo.Tipo_Trabajo (nombre_trabajo)
SELECT v.n FROM (VALUES ('Inspección'), ('Lavado tubería')) v(n)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Tipo_Trabajo t WHERE t.nombre_trabajo = v.n);

INSERT INTO dbo.Metodo_Pago (nombre_metodo)
SELECT v.n FROM (VALUES ('Depósito bancario')) v(n)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Metodo_Pago t WHERE t.nombre_metodo = v.n);

-- Aumento de tarifas aprobado el 1 de junio de 2026: antes de esa fecha se
-- facturaba con los montos anteriores (fn_ObtenerTarifaVigente los usa).
IF NOT EXISTS (SELECT 1 FROM dbo.Historial_Tarifa)
    INSERT INTO dbo.Historial_Tarifa (id_tarifa, monto_fijo_anterior, monto_fijo_nuevo, monto_por_m3_anterior,
                                      monto_por_m3_nuevo, fecha_cambio, id_usuario_sistema)
    SELECT t.id_tarifa, t.monto_fijo - 300, t.monto_fijo, ROUND(t.monto_por_m3 * 0.92 / 5, 0) * 5, t.monto_por_m3,
           '2026-06-01T08:00:00', dbo.fn_UsuarioActual()
    FROM dbo.Tarifa t WHERE t.activo = 1;

PRINT 'Empleados y usuarios...';
DECLARE @n int, @id int, @rol int, @usuario varchar(50), @tipo varchar(10);

DECLARE @ced varchar(20), @nom varchar(20), @a1 varchar(20), @a2 varchar(20), @puesto varchar(20),
        @tel varchar(15), @contr datetime;
SET @n = 1;
WHILE @n <= (SELECT MAX(n) FROM #emp)
BEGIN
    SELECT @ced = cedula, @nom = nombre, @a1 = ap1, @a2 = ap2, @puesto = puesto, @tel = tel,
           @contr = contratado, @usuario = usuario, @rol = r.id_rol
    FROM #emp e LEFT JOIN dbo.Rol r ON r.nombre_rol = e.rol WHERE e.n = @n;

    EXEC dbo.sp_AgregarEmpleado @cedula = @ced, @nombre_empleado = @nom, @apellido1_empleado = @a1,
         @apellido2_empleado = @a2, @puesto = @puesto, @telefono = @tel, @fecha_contratacion = @contr,
         @id_empleado = @id OUTPUT;
    UPDATE #emp SET id_empleado = @id WHERE n = @n;

    IF @usuario IS NOT NULL
        EXEC dbo.sp_CrearUsuarioSistema @id_empleado = @id, @id_rol = @rol, @nombre_usuario = @usuario,
             @contrasena = N'Demo#2026';
    SET @n += 1;
END

-- Último acceso de cada usuario en las últimas semanas.
UPDATE u SET fecha_ultimo_acceso = DATEADD(MINUTE, -((e.n * 977) % 30000) - 90, GETDATE())
FROM dbo.Usuario_Sistema u JOIN #emp e ON e.id_empleado = u.id_empleado;

PRINT 'Abonados, conexiones y medidores...';
DECLARE @clave varchar(5), @tid varchar(20), @ident varchar(20), @nombre varchar(50), @ap1 varchar(50),
        @ap2 varchar(50), @nac date, @dir varchar(200), @tel2 varchar(20), @correo varchar(100),
        @rced varchar(20), @rnom varchar(50), @rap1 varchar(50), @rap2 varchar(50);

DECLARE cur_ab CURSOR LOCAL FAST_FORWARD FOR SELECT clave FROM #ab ORDER BY clave;
OPEN cur_ab;
FETCH NEXT FROM cur_ab INTO @clave;
WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT @tid = tipo_id, @ident = ident, @nombre = nombre, @ap1 = ap1, @ap2 = ap2, @nac = nac, @dir = direccion,
           @tel2 = tel, @correo = correo, @rced = rep_ced, @rnom = rep_nom, @rap1 = rep_ap1, @rap2 = rep_ap2
    FROM #ab WHERE clave = @clave;

    EXEC dbo.sp_Nuevo_Abonado @tipo_identificacion = @tid, @numero_identidad = @ident, @nombre = @nombre,
         @apellido1 = @ap1, @apellido2 = @ap2, @fecha_nacimiento = @nac, @direccion = @dir, @telefono = @tel2,
         @correo_electronico = @correo, @cedula_representante = @rced, @nombre_representante = @rnom,
         @apellido1_representante = @rap1, @apellido2_representante = @rap2,
         @id_abonado = @id OUTPUT, @tipo_abonado = @tipo OUTPUT;
    UPDATE #ab SET id_abonado = @id, tipo_abonado = @tipo WHERE clave = @clave;
    FETCH NEXT FROM cur_ab INTO @clave;
END
CLOSE cur_ab;
DEALLOCATE cur_ab;

UPDATE f SET fecha_registro = DATEADD(HOUR, 9, CAST(a.registro AS datetime))
FROM dbo.Abonado_Fisico f JOIN #ab a ON a.tipo_abonado = 'FISICO' AND a.id_abonado = f.id_abonado_fisico;
UPDATE j SET fecha_registro = DATEADD(HOUR, 9, CAST(a.registro AS datetime))
FROM dbo.Abonado_Juridico j JOIN #ab a ON a.tipo_abonado = 'JURIDICO' AND a.id_abonado = j.id_abonado_juridico;

DECLARE @tarifa int, @ubic varchar(50), @id_abonado int, @c int, @m int, @serie varchar(20), @inicial decimal(10,2);
SET @n = 1;
WHILE @n <= (SELECT MAX(n) FROM #con)
BEGIN
    SELECT @ubic = c.ubicacion, @tipo = a.tipo_abonado, @id_abonado = a.id_abonado, @tarifa = t.id_tarifa,
           @inicial = CASE WHEN c.perfil = 'N' THEN 0 ELSE ((c.n * 397) % 900) + 120 END
    FROM #con c
    JOIN #ab a ON a.clave = c.abonado
    JOIN dbo.Tipo_Tarifa tt ON tt.nombre_tarifa = c.tarifa
    JOIN dbo.Tarifa t ON t.id_tipo_tarifa = tt.id_tipo_tarifa AND t.activo = 1
    WHERE c.n = @n;

    EXEC dbo.sp_RegistrarConexion @tipo_abonado = @tipo, @id_abonado = @id_abonado, @id_tarifa = @tarifa,
         @ubicacion = @ubic, @id_conexion = @c OUTPUT;
    SET @serie = CONCAT('SC-', 24000 + @n);
    EXEC dbo.sp_AsignarMedidorConexion @id_conexion = @c, @numero_serie = @serie, @lectura_inicial = @inicial,
         @sustituir = 0, @id_medidor = @m OUTPUT;
    UPDATE #con SET id_conexion = @c, id_medidor = @m WHERE n = @n;
    SET @n += 1;
END

UPDATE x SET fecha_conexion = DATEADD(HOUR, 10, CAST(c.desde AS datetime))
FROM dbo.Conexion x JOIN #con c ON c.id_conexion = x.id_conexion;
UPDATE x SET fecha_instalacion = DATEADD(HOUR, 11, CAST(c.desde AS datetime)), fecha_ultima_lectura = NULL
FROM dbo.Medidor x JOIN #con c ON c.id_medidor = x.id_medidor;

PRINT 'Lecturas, facturas y pagos (un año)...';
DECLARE @efectivo int, @sinpe int, @transf int, @tarjeta int, @deposito int;
SELECT @efectivo = id_metodo_pago FROM dbo.Metodo_Pago WHERE nombre_metodo = 'Efectivo';
SELECT @sinpe    = id_metodo_pago FROM dbo.Metodo_Pago WHERE nombre_metodo LIKE 'SINPE%';
SELECT @transf   = id_metodo_pago FROM dbo.Metodo_Pago WHERE nombre_metodo = 'Transferencia bancaria';
SELECT @tarjeta  = id_metodo_pago FROM dbo.Metodo_Pago WHERE nombre_metodo = 'Tarjeta';
SELECT @deposito = id_metodo_pago FROM dbo.Metodo_Pago WHERE nombre_metodo = 'Depósito bancario';

DECLARE @perfil char(1), @desde date, @base decimal(10,2), @corte date, @fin date, @dia int,
        @mes date, @ultimo_mes date, @fecha datetime, @consumo decimal(10,2), @lectura decimal(10,2),
        @id_lectura int, @id_factura int, @emision datetime, @vence date, @h int, @metodo int,
        @fecha_pago date, @fecha_resto date, @saldo decimal(10,2), @id_recargo int, @hoy date = CAST(GETDATE() AS date),
        @estacion decimal(4,2), @pico decimal(4,2);

SET @n = 1;
WHILE @n <= (SELECT MAX(n) FROM #con)
BEGIN
    SELECT @clave = clave, @perfil = perfil, @desde = desde, @base = base, @corte = corte, @fin = fin, @dia = dia,
           @c = id_conexion, @m = id_medidor
    FROM #con WHERE n = @n;

    -- Primer mes: noviembre 2025, o el mes siguiente a la instalación.
    SET @mes = CASE WHEN @desde < '2025-10-15' THEN '2025-11-01'
                    ELSE DATEADD(MONTH, 1, DATEFROMPARTS(YEAR(@desde), MONTH(@desde), 1)) END;
    -- Último mes: noviembre 2026 solo si ese medidor ya se leyó (días 2 y 3).
    SET @ultimo_mes = COALESCE(@fin, CASE WHEN @dia <= 3 AND @clave <> 'F23' THEN '2026-11-01' ELSE '2026-10-01' END);

    WHILE @mes <= @ultimo_mes
    BEGIN
        SET @h = ABS(CHECKSUM(CONCAT(@clave, '|', @mes)));
        SET @fecha = DATEADD(MINUTE, 480 + (@h % 180), CAST(DATEADD(DAY, @dia - 1, @mes) AS datetime));

        -- Cambio de medidor de F08 en junio 2026 (ver incidencia "Medidor dañado").
        IF @clave = 'F08' AND @mes = '2026-07-01'
        BEGIN
            DECLARE @nuevo int;
            SET @serie = CONCAT('SC-', 24000 + @n, '-B');
            EXEC dbo.sp_AsignarMedidorConexion @id_conexion = @c, @numero_serie = @serie, @lectura_inicial = 0,
                 @sustituir = 1, @id_medidor = @nuevo OUTPUT;
            UPDATE dbo.Medidor SET fecha_instalacion = '2026-06-14T10:30:00' WHERE id_medidor = @nuevo;
            UPDATE #con SET id_medidor_viejo = @m, id_medidor = @nuevo WHERE n = @n;
            SET @m = @nuevo;
        END

        -- Verano (diciembre a abril) se consume más; las escuelas bajan en vacaciones.
        SET @estacion = CHOOSE(MONTH(@mes), 1.20, 1.25, 1.30, 1.30, 1.10, 0.95, 0.90, 0.90, 0.90, 0.90, 0.95, 1.10);
        IF @clave IN ('J03', 'J04') AND MONTH(@mes) IN (12, 1) SET @estacion = 0.45;
        SET @pico = ISNULL((SELECT factor FROM #pico WHERE clave = @clave AND mes = @mes), 1);
        SET @consumo = ROUND(@base * @estacion * @pico * (0.90 + (@h % 21) / 100.0), 0);
        IF @consumo < 1 SET @consumo = 1;
        SET @lectura = dbo.fn_ObtenerUltimaLectura(@m) + @consumo;

        EXEC dbo.sp_RegistrarLectura @id_medidor = @m, @lectura_actual = @lectura, @fecha_lectura = @fecha,
             @id_lectura = @id_lectura OUTPUT;
        EXEC dbo.sp_GenerarFactura @id_lectura = @id_lectura, @id_factura = @id_factura OUTPUT;

        -- La factura se emite al día siguiente de la lectura, con 15 días de plazo.
        SET @emision = CASE WHEN DATEADD(DAY, 1, @fecha) > GETDATE() THEN GETDATE() ELSE DATEADD(DAY, 1, @fecha) END;
        SET @vence = DATEADD(DAY, 15, CAST(@emision AS date));
        UPDATE dbo.Factura SET fecha_emision = @emision, fecha_vencimiento = @vence WHERE id_factura = @id_factura;

        -- Método de pago: los negocios usan más transferencia.
        SET @metodo = CASE
            WHEN @clave LIKE 'J%' AND @h % 100 < 55 THEN @transf
            WHEN @h % 100 < 35 THEN @efectivo
            WHEN @h % 100 < 72 THEN @sinpe
            WHEN @h % 100 < 88 THEN @transf
            WHEN @h % 100 < 95 THEN @tarjeta
            ELSE @deposito END;

        SET @fecha_pago = NULL;
        SET @fecha_resto = NULL;
        IF @perfil IN ('P', 'N', 'I') OR (@perfil = 'M' AND @mes < @corte)
            SET @fecha_pago = DATEADD(DAY, 2 + (@h % 11), CAST(@emision AS date));
        ELSE IF @perfil = 'T'
            SET @fecha_pago = DATEADD(DAY, CASE WHEN @h % 3 = 0 THEN 6 ELSE 18 + (@h % 20) END, CAST(@emision AS date));
        ELSE IF @perfil = 'A'
        BEGIN
            SET @fecha_pago  = DATEADD(DAY, 8,  CAST(@emision AS date));
            SET @fecha_resto = DATEADD(DAY, 30 + (@h % 15), CAST(@emision AS date));
        END

        -- Pago (completo o primer abono).
        IF @fecha_pago IS NOT NULL AND @fecha_pago <= @hoy
        BEGIN
            IF @fecha_pago > @vence
            BEGIN
                SET @id_recargo = NULL;
                EXEC dbo.sp_CalcularRecargoMora @id_factura = @id_factura, @fecha_corte = @fecha_pago, @id_recargo = @id_recargo OUTPUT;
                UPDATE dbo.Recargo_mora SET fecha_calculo = @fecha_pago WHERE id_recargo = @id_recargo;
            END
            SET @saldo = dbo.fn_CalcularSaldoPendiente(@id_factura);
            IF @perfil = 'A' SET @saldo = ROUND(@saldo * 0.6, 0);
            EXEC dbo.sp_RegistrarPago @id_factura = @id_factura, @id_metodo_pago = @metodo, @monto = @saldo, @fecha_pago = @fecha_pago;
        END

        -- Segundo abono de los que pagan por partes (ya vencido: lleva recargo).
        IF @fecha_resto IS NOT NULL AND @fecha_resto <= @hoy
        BEGIN
            SET @id_recargo = NULL;
            EXEC dbo.sp_CalcularRecargoMora @id_factura = @id_factura, @fecha_corte = @fecha_resto, @id_recargo = @id_recargo OUTPUT;
            UPDATE dbo.Recargo_mora SET fecha_calculo = @fecha_resto WHERE id_recargo = @id_recargo;
            SET @saldo = dbo.fn_CalcularSaldoPendiente(@id_factura);
            EXEC dbo.sp_RegistrarPago @id_factura = @id_factura, @id_metodo_pago = @efectivo, @monto = @saldo, @fecha_pago = @fecha_resto;
        END

        SET @mes = DATEADD(MONTH, 1, @mes);
    END
    SET @n += 1;
END

PRINT 'Incidencias y mantenimientos...';
DECLARE @tipo_inc int, @desc varchar(100), @ubi varchar(20), @fecha_inc datetime, @trabajo int, @emp int,
        @ini datetime, @fin_m datetime, @estado_m varchar(20), @estado_f varchar(20), @sol varchar(400),
        @id_alerta int, @id_inc int, @id_mant int, @fontanero_base int, @horas_i int, @horas_d int, @ini_fijo datetime;

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

PRINT 'Estados de conexiones, usuarios y empleados...';
-- F20 se trasladó: se retira el medidor y la conexión queda inactiva.
SELECT @c = id_conexion, @m = id_medidor FROM #con WHERE clave = 'F20';
EXEC dbo.sp_DesactivarMedidor @id_medidor = @m, @nuevo_estado = 'Retirado', @motivo = 'El abonado se trasladó a otra provincia.';
EXEC dbo.sp_CambiarEstadoConexion @id_conexion = @c, @nuevo_estado = 'Inactiva', @motivo = 'Baja solicitada por traslado del abonado.';
UPDATE dbo.Conexion SET fecha_modificacion = '2026-08-10T11:00:00' WHERE id_conexion = @c;

-- F23 tiene más de 90 días de atraso: corte del servicio.
SELECT @c = id_conexion FROM #con WHERE clave = 'F23';
EXEC dbo.sp_CambiarEstadoConexion @id_conexion = @c, @nuevo_estado = 'Cortada', @motivo = 'Corte por morosidad (más de 90 días de atraso).';
UPDATE dbo.Conexion SET fecha_modificacion = '2026-10-20T10:30:00' WHERE id_conexion = @c;

-- Un miembro de la Junta terminó su periodo y un ayudante renunció.
SELECT @id = u.id_usuario_sistema FROM dbo.Usuario_Sistema u WHERE u.nombre_usuario = 'hernan.juarez';
EXEC dbo.sp_DesactivarUsuarioSistema @id_usuario_sistema = @id;
SELECT @id = id_empleado FROM #emp WHERE n = 7;
EXEC dbo.sp_CambiarEstadoEmpleado @id_empleado = @id, @activo = 0;

-- Un pago aplicado a la factura equivocada: se anula y se registra de nuevo.
DECLARE @id_pago int, @monto decimal(10,2);
SELECT TOP (1) @id_pago = p.id_pago, @id_factura = p.id_factura, @monto = p.monto, @metodo = p.id_metodo_pago, @fecha_pago = p.fecha_pago
FROM dbo.Pago p
JOIN dbo.Factura f ON f.id_factura = p.id_factura
JOIN dbo.Lectura l ON l.id_lectura = f.id_lectura
JOIN #con c ON c.id_medidor = l.id_medidor
WHERE c.clave = 'F03' AND p.fecha_pago >= '2026-09-01'
ORDER BY p.id_pago;
IF @id_pago IS NOT NULL
BEGIN
    EXEC dbo.sp_AnularPago @id_pago = @id_pago, @motivo = 'El cajero lo aplicó a otra factura; se registra de nuevo.';
    EXEC dbo.sp_RegistrarPago @id_factura = @id_factura, @id_metodo_pago = @metodo, @monto = @monto, @fecha_pago = @fecha_pago;
END

COMMIT;
PRINT 'Carga principal confirmada.';
GO

   --Procesos de cierre (los mismos que corren los jobs nocturnos)
PRINT 'Facturas vencidas, prórroga, recargos y suspensiones...';
EXEC dbo.sp_ActualizarFacturasVencidas;

-- La Asociación de Desarrollo pidió un arreglo de pago para su factura vencida.
DECLARE @f int, @nueva date = DATEADD(DAY, 10, CAST(GETDATE() AS date));
SELECT TOP (1) @f = f.id_factura
FROM dbo.Factura f
JOIN dbo.Lectura l ON l.id_lectura = f.id_lectura
JOIN #con c ON c.id_medidor = l.id_medidor
WHERE c.clave = 'J05' AND f.estado = 'Vencida'
ORDER BY f.fecha_emision DESC;
IF @f IS NOT NULL
    EXEC dbo.sp_OtorgarProrroga @id_factura = @f, @nueva_fecha_vencimiento = @nueva,
         @motivo = 'Arreglo de pago aprobado por la Junta Directiva.';

EXEC dbo.sp_AplicarRecargosMoraMasivo;
EXEC dbo.sp_SuspenderConexionesMorosas;
GO

PRINT 'Carga completa del Data Warehouse...';
EXEC dbo.sp_EjecutarCargaDW @carga_completa = 1;
GO

PRINT 'Respaldos diferencial y de log...';
DECLARE @politica int;
SELECT @politica = p.id_politica FROM dbo.Politica_Respaldo p
JOIN dbo.Tipo_Respaldo t ON t.id_tipo_respaldo = p.id_tipo_respaldo
WHERE t.nombre_respaldo = 'Diferencial' AND p.activo = 1;
EXEC dbo.sp_EjecutarRespaldo @id_politica = @politica;

SELECT @politica = p.id_politica FROM dbo.Politica_Respaldo p
JOIN dbo.Tipo_Respaldo t ON t.id_tipo_respaldo = p.id_tipo_respaldo
WHERE t.nombre_respaldo = 'Log' AND p.activo = 1;
EXEC dbo.sp_EjecutarRespaldo @id_politica = @politica;
GO

EXEC sys.sp_set_session_context @key = N'id_usuario_sistema', @value = NULL;
EXEC sys.sp_set_session_context @key = N'id_empleado', @value = NULL;
PRINT 'Datos de demostración cargados. Usuarios nuevos con contraseña Demo#2026.';
GO
SET NOEXEC OFF;
GO
