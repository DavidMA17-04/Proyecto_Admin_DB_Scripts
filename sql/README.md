# Sistema de Gestión para una ASADA — Scripts SQL Server

Implementación en SQL Server de las secciones 6, 12 y 14 del documento *Proyecto Admin BD*.

## Instalación

Requisitos: SQL Server 2019 o superior (Developer, Standard o Express) y SSMS o `sqlcmd`.

1. Revise la ruta de respaldos en `16_datos_iniciales.sql` (`@ruta_respaldos`). La carpeta debe existir.
2. Ejecute `ejecutar_todo.sql` en **modo SQLCMD** (SSMS: menú *Consulta → Modo SQLCMD*), o desde la consola:

   ```
   sqlcmd -S localhost -E -f 65001 -i ejecutar_todo.sql
   ```

3. Si el servidor tiene SQL Server Agent, ejecute `17_jobs_sql_agent.sql` para crear las tareas programadas.

Usuarios iniciales de la aplicación (cámbielos con `sp_CambiarContrasenaUsuario`):

| Usuario | Contraseña     | Rol                       |
|---------|----------------|---------------------------|
| admin   | Asada#2026     | Administrador del Sistema |
| dba     | AsadaDBA#2026  | Administrador de BD       |
| fontanero | Fontanero#2026 | Fontanero               |
| junta   | Junta#2026     | Junta Directiva           |

## Probar

```sql
USE ASADA;
EXEC dbo.sp_CargarDatosPrueba;   -- 4 abonados, 6 meses de lecturas, facturas, pagos, mora, incidencias
EXEC dbo.sp_EjecutarPruebas;     -- 25 casos; cada uno se revierte con ROLLBACK
EXEC dbo.sp_EjecutarCargaDW;     -- ETL hacia ASADA_DW
EXEC dbo.sp_LimpiarDatosPrueba;  -- deja la base como estaba
```

## Contenido

| Script | Contenido |
|---|---|
| 00 | Bases `ASADA` (recuperación FULL, necesaria para Point-in-Time) y `ASADA_DW` |
| 01 | 35 tablas con llaves primarias, foráneas y restricciones CHECK |
| 02 | Índices (sección 12) |
| 03 | Funciones |
| 04 | Vistas |
| 05–12 | Procedimientos por módulo: abonados y conexiones, lecturas y facturación, pagos y mora, incidencias y mantenimientos, seguridad y bitácora, catálogos, consumo anómalo, respaldos |
| 13 | Tablas del Data Warehouse y procesos ETL |
| 14 | Triggers de auditoría, historial y reglas automáticas |
| 15 | Mantenimiento de índices, integridad, monitoreo y roles de base de datos |
| 16 | Datos iniciales: catálogos, tarifas, roles y permisos según la matriz de acceso, políticas de respaldo |
| 17 | Jobs de SQL Server Agent (respaldos, ETL, mantenimiento nocturno) |
| 18 | Datos de prueba, limpieza y casos de prueba |

## Cómo se registra quién hace cada cambio

La aplicación llama a `sp_IniciarSesion`, que valida la contraseña y guarda el usuario y el empleado en `SESSION_CONTEXT`. Los triggers leen esos valores (`fn_UsuarioActual`, `fn_EmpleadoActual`) y los escriben en `Bitacora`, `Historial_Incidencia` e `Historial_Mantenimiento`. Las acciones de procesos automáticos (jobs, ETL) quedan con usuario `NULL` y se muestran como "SISTEMA".

## Diferencias con el diccionario de datos (sección 14)

Algunos objetos de la sección 12 necesitan columnas que el diccionario no tiene. En `01_tablas.sql` están marcadas con `-- [AGREGADO]`. Conviene actualizar el documento con esta lista.

| Tabla | Cambio | Por qué |
|---|---|---|
| Pago | `monto`, `estado`, `motivo_anulacion` | El diccionario no guarda cuánto se pagó; `CK_Pago_MontoPositivo` y `sp_AnularPago` lo requieren |
| Usuario_Sistema | `intentos_fallidos`, `fecha_ultimo_acceso` | Los usan `sp_RegistrarInicioSesion` y `sp_RegistrarIntentoFallido` |
| Usuario_Sistema | `contrasena_usuario` pasa de varchar(50) a varchar(64) | Se guarda el hash SHA2-256 (64 caracteres), no la contraseña en claro |
| Historial_Tarifa | Tabla nueva | La usa `sp_ConsultarHistorialTarifa` y no está en el diccionario |
| Tarifa, Tipo_Tarifa, Tipo_Trabajo, Tipo_Incidencia, Metodo_Pago | `activo` | Bajas lógicas y consultas de "activos" |
| Abonado_Fisico, Abonado_Juridico | `activo` | Eliminación lógica (R1-01) |
| Medidor | `ultima_lectura`, `fecha_ultima_lectura` | Las mantiene `trg_ActualizarUltimaLectura` |
| Recargo_mora | `monto_recargo`, `estado`, `motivo_anulacion` | `sp_AnularRecargoMora` y el cálculo del saldo |
| Incidencia | `prioridad` | Resultado de `fn_ClasificarIncidencia` |
| Alerta_Consumo | `id_incidencia` | R9: vincular la alerta con una incidencia |
| Alerta_Consumo | `porcentaje_variacion` pasa de decimal(5,2) a decimal(7,2) | Una variación puede superar 999.99 % |
| Tipo_Respaldo | `nombre_respaldo` pasa de varchar(10) a varchar(15) | "Diferencial" tiene 11 caracteres |
| Bitacora | `tabla_afectada`; `id_usuario_sistema` admite NULL | `sp_ConsultarBitacora` filtra por tabla; los procesos automáticos no tienen usuario |
| Control_ETL | `reintentado` | La usa `vw_CargasFallidas` |
| FACT_* del DW | `id_*_origen` | Carga incremental sin duplicados |
| Campos `text` | Se usan como `varchar(max)` | `text` está obsoleto y no se puede leer en triggers |
| Lectura.consumo, Factura.monto_total | Columnas calculadas | Garantizan que siempre cuadren con sus componentes |

## Reglas de negocio que se asumieron

Estos valores no están definidos en el documento. Se pueden ajustar:

- **Recargo por mora** (`fn_CalcularPorcentajeMora`): 2 % de 1 a 30 días, 4 % de 31 a 60 y 6 % después. Cada factura tiene un solo recargo vigente, que se recalcula sobre el saldo sin recargos.
- **Plazo de pago**: 15 días desde la emisión (`sp_GenerarFactura @dias_plazo`).
- **Bloqueo de cuenta**: 3 intentos fallidos.
- **Contraseña**: mínimo 8 caracteres, con mayúscula, minúscula, número y símbolo.
- **Consumo anómalo**: tres reglas iniciales (50 %, 100 % y 200 % sobre el promedio de 3 meses). Un medidor sin historial no genera alerta.
- **Distrito** en el DW: se toma lo que está antes de la primera coma de la dirección o ubicación (`fn_ExtraerDistrito`), porque el modelo no tiene un campo de distrito.
- **Restauración Point-in-Time**: `sp_RestaurarPuntoEnTiempo` restaura en una base aparte (`ASADA_Restaurada`) para revisar antes de reemplazar la productiva. Con `@solo_generar_script = 1` devuelve el script para ejecutarlo desde `master`.
