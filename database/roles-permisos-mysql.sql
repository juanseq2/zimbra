-- Roles MySQL con privilegios mínimos para la API de Zimbra.
-- Antes de ejecutar:
-- 1. Selecciona la base usada por la API; cambia `defaultdb` si DB_NAME es distinto.
-- 2. Crea en Aiven el usuario zimbra_app con host % y una contraseña privada.
--    No guardes esa contraseña en este archivo.

CREATE ROLE IF NOT EXISTS 'zimbra_lectura', 'zimbra_operador';

GRANT SELECT ON `defaultdb`.`usuario_sistema` TO 'zimbra_lectura';
GRANT SELECT ON `defaultdb`.`campania_marketing` TO 'zimbra_lectura';
GRANT SELECT ON `defaultdb`.`cliente_prospecto` TO 'zimbra_lectura';
GRANT SELECT ON `defaultdb`.`actividad_web` TO 'zimbra_lectura';
GRANT SELECT ON `defaultdb`.`propuesta` TO 'zimbra_lectura';
GRANT SELECT ON `defaultdb`.`venta` TO 'zimbra_lectura';
GRANT SELECT ON `defaultdb`.`factura` TO 'zimbra_lectura';
GRANT SELECT ON `defaultdb`.`notificacion` TO 'zimbra_lectura';
GRANT SELECT ON `defaultdb`.`crm_outbox` TO 'zimbra_lectura';
GRANT SELECT ON `defaultdb`.`cliente_persona_natural` TO 'zimbra_lectura';
GRANT SELECT ON `defaultdb`.`v_tasa_conversion` TO 'zimbra_lectura';
GRANT SELECT ON `defaultdb`.`v_reporte_mensual_ventas` TO 'zimbra_lectura';
GRANT EXECUTE ON PROCEDURE `defaultdb`.`sp_reporte_mensual_ventas` TO 'zimbra_lectura';

GRANT INSERT ON `defaultdb`.`cliente_prospecto` TO 'zimbra_operador';
GRANT INSERT ON `defaultdb`.`actividad_web` TO 'zimbra_operador';
GRANT INSERT ON `defaultdb`.`propuesta` TO 'zimbra_operador';
GRANT INSERT ON `defaultdb`.`notificacion` TO 'zimbra_operador';
GRANT INSERT ON `defaultdb`.`crm_outbox` TO 'zimbra_operador';
GRANT INSERT ON `defaultdb`.`cliente_persona_natural` TO 'zimbra_operador';
GRANT INSERT ON `defaultdb`.`usuario_sistema` TO 'zimbra_operador';
GRANT UPDATE (`puntaje_interes`, `id_usuario_asignado`, `estado_prospecto`)
    ON `defaultdb`.`cliente_prospecto` TO 'zimbra_operador';
GRANT UPDATE (`id_cliente`, `visitor_id`) ON `defaultdb`.`actividad_web` TO 'zimbra_operador';
GRANT UPDATE (`estado_propuesta`) ON `defaultdb`.`propuesta` TO 'zimbra_operador';
GRANT UPDATE (`leida`) ON `defaultdb`.`notificacion` TO 'zimbra_operador';
GRANT UPDATE (`estado`, `intentos`, `proximo_intento`, `ultimo_error`)
    ON `defaultdb`.`crm_outbox` TO 'zimbra_operador';
GRANT UPDATE (`nombre`, `email`, `password_hash`, `rol`, `activo`, `ultimo_acceso`)
    ON `defaultdb`.`usuario_sistema` TO 'zimbra_operador';
GRANT SELECT ON `defaultdb`.`usuario_sistema` TO 'zimbra_operador';
GRANT EXECUTE ON PROCEDURE `defaultdb`.`sp_cerrar_venta` TO 'zimbra_operador';

GRANT 'zimbra_lectura', 'zimbra_operador' TO 'zimbra_app'@'%';
SET DEFAULT ROLE ALL TO 'zimbra_app'@'%';

SHOW GRANTS FOR 'zimbra_app'@'%';
