# Guía de sustentación: Zimbra Ventas

## Preparación

1. Confirma que el usuario MySQL `zimbra_app` existe en Aiven y tiene los roles
   definidos en `roles-permisos-mysql.sql`.
2. Configura `DB_USER=zimbra_app` y la contraseña asignada en el `.env` local de
   `zimbra-api`. No muestres ni compartas ese archivo.
3. Inicia frontend y API desde `zimbra\` con `npm run dev:all`.
4. Comprueba `http://localhost:3000/api/health`; debe indicar que la base está
   conectada.
5. Usa datos de demostración existentes o prepara datos en una base de pruebas.
   No cierres ventas reales durante la exposición.

## Demostración práctica

1. **Base de datos:** muestra las vistas `v_tasa_conversion` y
   `v_reporte_mensual_ventas`, los índices con `indices-mysql.sql`, el plan de
   consulta con `EXPLAIN` y los permisos efectivos con `SHOW GRANTS`.
2. **Backend:** muestra el health check y las rutas de ventas, propuestas,
   conversión y reporte mensual.
3. **Frontend:** presenta la tabla de ventas, las barras de conversión por
   campaña, los ingresos por vendedor y la actualización del panel.
4. **Concurrencia:** usa dos sesiones MySQL para mostrar que `SELECT ... FOR
   UPDATE` bloquea la misma propuesta mientras la primera transacción permanece
   abierta.

## Simulación de bloqueo sin modificar ventas

Elige un `id_propuesta` existente. Abre dos sesiones MySQL y usa el mismo ID en
ambas. Esta prueba solo bloquea la fila durante unos segundos; no actualiza datos.

**Sesión A** — ejecútala primero:

```sql
SET @id_propuesta_prueba = 1;
START TRANSACTION;
SELECT id_propuesta
FROM propuesta
WHERE id_propuesta = @id_propuesta_prueba
FOR UPDATE;
SELECT SLEEP(15);
ROLLBACK;
```

Reemplaza `1` por un ID existente. Mientras la sesión A está esperando en
`SLEEP`, ejecuta en la **sesión B**:

```sql
SET @id_propuesta_prueba = 1;
START TRANSACTION;
SELECT id_propuesta
FROM propuesta
WHERE id_propuesta = @id_propuesta_prueba
FOR UPDATE;
ROLLBACK;
```

La consulta de la sesión B debe esperar hasta que la sesión A haga `ROLLBACK`.
El procedimiento `sp_cerrar_venta` usa el mismo bloqueo de fila y confirma la
venta con una transacción. No pruebes ese procedimiento concurrentemente en
producción: una llamada exitosa crea una venta.

## Reparto sugerido del equipo

- **Integrante 1:** modelo MySQL, índices y permisos.
- **Integrante 2:** API, validación de conexión y procedimientos.
- **Integrante 3:** panel, tablas y gráficos.
- **Integrante 4:** simulación de concurrencia y coordinación de la demo.

Cada integrante debe explicar una parte y participar en las preguntas finales.
