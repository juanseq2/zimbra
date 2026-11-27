-- Consultas de diagnóstico de solo lectura para MySQL / Aiven.
-- No modifica ni elimina datos.

SELECT 1 AS conexion_mysql;

SELECT id_venta, fecha_cierre, monto_final
FROM venta
ORDER BY id_venta;

SELECT p.id_propuesta, p.id_cliente, p.id_usuario, p.monto_estimado, p.estado_propuesta
FROM propuesta AS p
LEFT JOIN venta AS v ON v.id_propuesta = p.id_propuesta
WHERE p.estado_propuesta = 'aceptada'
  AND v.id_venta IS NULL
ORDER BY p.id_propuesta;

EXPLAIN
SELECT p.id_propuesta, p.id_cliente, p.id_usuario, p.monto_estimado, p.estado_propuesta
FROM propuesta AS p
LEFT JOIN venta AS v ON v.id_propuesta = p.id_propuesta
WHERE p.estado_propuesta = 'aceptada'
  AND v.id_venta IS NULL
ORDER BY p.id_propuesta;

EXPLAIN
SELECT id_venta, fecha_cierre, monto_final
FROM venta
WHERE fecha_cierre >= DATE_FORMAT(CURRENT_DATE(), '%Y-%m-01')
ORDER BY fecha_cierre;

SELECT *
FROM v_tasa_conversion
ORDER BY id_campania;

SELECT cp.id_cliente, cp.nombre, cp.correo_electronico, cp.estado_prospecto,
       cp.puntaje_interes, cp.id_usuario_asignado,
       DATE_ADD(cp.fecha_registro, INTERVAL cp.duracion_prueba_dias DAY) AS fecha_fin_prueba
FROM cliente_prospecto AS cp
ORDER BY cp.fecha_registro DESC;

SELECT estado, COUNT(*) AS cantidad_eventos
FROM crm_outbox
GROUP BY estado;

SELECT id_factura, numero_factura, id_venta, monto, fecha_emision
FROM factura
ORDER BY fecha_emision DESC;

SELECT vendedor, cantidad_ventas, ingreso_total
FROM v_reporte_mensual_ventas
ORDER BY ingreso_total DESC;

CALL sp_reporte_mensual_ventas(MONTH(CURRENT_DATE()), YEAR(CURRENT_DATE()));
