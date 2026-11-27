-- Migración aditiva del flujo funcional Zimbra para MySQL 8.
-- Ejecutar UNA sola vez en la base existente, después de crear un respaldo.
-- No elimina ni cambia filas; agrega columnas/tablas y reemplaza sp_cerrar_venta.
-- No ejecutar junto con zimbra-mysql.sql: este archivo migra el esquema ya existente.

ALTER TABLE cliente_prospecto
    ADD COLUMN puntaje_interes SMALLINT UNSIGNED NOT NULL DEFAULT 0 AFTER duracion_prueba_dias,
    ADD COLUMN id_usuario_asignado INT NULL AFTER id_campania,
    ADD KEY idx_cliente_asignado_estado (id_usuario_asignado, estado_prospecto),
    ADD CONSTRAINT fk_cliente_usuario_asignado
        FOREIGN KEY (id_usuario_asignado) REFERENCES usuario_sistema (id_usuario)
        ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE actividad_web
    MODIFY COLUMN id_cliente INT NULL,
    ADD COLUMN visitor_id CHAR(36) NULL AFTER id_cliente,
    ADD KEY idx_actividad_visitante_fecha (visitor_id, fecha_actividad);

CREATE TABLE IF NOT EXISTS notificacion (
    id_notificacion BIGINT NOT NULL AUTO_INCREMENT,
    id_usuario INT NOT NULL,
    id_cliente INT,
    tipo VARCHAR(40) NOT NULL,
    mensaje VARCHAR(255) NOT NULL,
    leida BOOLEAN NOT NULL DEFAULT FALSE,
    creada_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_notificacion),
    KEY idx_notificacion_usuario_fecha (id_usuario, creada_en),
    CONSTRAINT fk_notificacion_usuario FOREIGN KEY (id_usuario)
        REFERENCES usuario_sistema (id_usuario) ON DELETE RESTRICT,
    CONSTRAINT fk_notificacion_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente_prospecto (id_cliente) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS factura (
    id_factura INT NOT NULL AUTO_INCREMENT,
    id_venta INT NOT NULL,
    numero_factura VARCHAR(40) NOT NULL,
    monto DECIMAL(14, 2) NOT NULL,
    fecha_emision TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    estado VARCHAR(20) NOT NULL DEFAULT 'emitida',
    PRIMARY KEY (id_factura),
    UNIQUE KEY uq_factura_venta (id_venta),
    UNIQUE KEY uq_factura_numero (numero_factura),
    CONSTRAINT chk_factura_monto CHECK (monto > 0),
    CONSTRAINT fk_factura_venta FOREIGN KEY (id_venta)
        REFERENCES venta (id_venta) ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS crm_outbox (
    id_evento BIGINT NOT NULL AUTO_INCREMENT,
    clave_idempotencia CHAR(36) NOT NULL,
    tipo_evento VARCHAR(60) NOT NULL,
    payload JSON NOT NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'pendiente',
    intentos TINYINT UNSIGNED NOT NULL DEFAULT 0,
    proximo_intento TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ultimo_error VARCHAR(1000),
    creado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id_evento),
    UNIQUE KEY uq_crm_idempotencia (clave_idempotencia),
    KEY idx_crm_pendiente (estado, proximo_intento),
    CONSTRAINT chk_crm_estado CHECK (estado IN ('pendiente', 'procesando', 'sincronizado', 'error'))
) ENGINE=InnoDB;

DROP PROCEDURE IF EXISTS sp_cerrar_venta;
DELIMITER $$
CREATE PROCEDURE sp_cerrar_venta(
    IN p_id_propuesta INT,
    IN p_id_usuario INT,
    IN p_monto_final DECIMAL(14, 2),
    IN p_metodo_pago VARCHAR(40),
    OUT p_venta_creada_id INT
)
BEGIN
    DECLARE v_cliente INT DEFAULT NULL;
    DECLARE v_estado VARCHAR(20);
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_cliente = NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
    SELECT id_cliente, estado_propuesta
      INTO v_cliente, v_estado
      FROM propuesta
     WHERE id_propuesta = p_id_propuesta
       FOR UPDATE;

    IF v_cliente IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La propuesta indicada no existe.';
    END IF;

    IF v_estado <> 'aceptada' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La propuesta no está aceptada.';
    END IF;

    INSERT INTO venta (id_propuesta, id_usuario, monto_final, metodo_pago)
    VALUES (p_id_propuesta, p_id_usuario, p_monto_final, p_metodo_pago);

    SET p_venta_creada_id = LAST_INSERT_ID();

    UPDATE cliente_prospecto
       SET estado_prospecto = 'cliente_comercial'
     WHERE id_cliente = v_cliente;

    INSERT INTO factura (id_venta, numero_factura, monto)
    VALUES (
        p_venta_creada_id,
        CONCAT('ZIM-', DATE_FORMAT(CURRENT_DATE(), '%Y'), '-', p_venta_creada_id),
        p_monto_final
    );

    INSERT INTO crm_outbox (clave_idempotencia, tipo_evento, payload)
    VALUES (
        UUID(),
        'venta.cerrada',
        JSON_OBJECT(
            'evento', 'venta.cerrada',
            'id_venta', p_venta_creada_id,
            'id_factura', LAST_INSERT_ID(),
            'numero_factura', CONCAT('ZIM-', DATE_FORMAT(CURRENT_DATE(), '%Y'), '-', p_venta_creada_id),
            'id_propuesta', p_id_propuesta,
            'id_cliente', v_cliente,
            'id_usuario', p_id_usuario,
            'monto', p_monto_final,
            'metodo_pago', p_metodo_pago
        )
    );
    COMMIT;
END$$
DELIMITER ;
