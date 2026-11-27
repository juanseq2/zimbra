-- Esquema MySQL para Zimbra / Aiven.
-- Requiere MySQL 8.0.16 o posterior. No elimina ni inserta datos.
-- Las tablas existentes no se modifican; revisa su estructura antes de ejecutar.

CREATE TABLE IF NOT EXISTS usuario_sistema (
    id_usuario INT NOT NULL AUTO_INCREMENT,
    nombre VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL,
    rol VARCHAR(20) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id_usuario),
    UNIQUE KEY uq_usuario_email (email),
    CONSTRAINT chk_usuario_rol CHECK (rol IN ('administrador', 'vendedor', 'invitado'))
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS campania_marketing (
    id_campania INT NOT NULL AUTO_INCREMENT,
    nombre_campania VARCHAR(120) NOT NULL,
    canal VARCHAR(50) NOT NULL,
    fecha_inicio DATE,
    PRIMARY KEY (id_campania)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS cliente_prospecto (
    id_cliente INT NOT NULL AUTO_INCREMENT,
    correo_electronico VARCHAR(150) NOT NULL,
    nombre VARCHAR(120) NOT NULL,
    empresa VARCHAR(120),
    estado_prospecto VARCHAR(20) NOT NULL DEFAULT 'nuevo',
    duracion_prueba_dias INT NOT NULL DEFAULT 60,
    puntaje_interes SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    fecha_registro TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    id_campania INT,
    id_usuario_asignado INT,
    PRIMARY KEY (id_cliente),
    UNIQUE KEY uq_cliente_correo (correo_electronico),
    KEY idx_cliente_estado (estado_prospecto),
    KEY idx_cliente_campania (id_campania),
    KEY idx_cliente_asignado_estado (id_usuario_asignado, estado_prospecto),
    CONSTRAINT chk_cliente_estado CHECK (
        estado_prospecto IN ('nuevo', 'calificado', 'descartado', 'cliente_comercial')
    ),
    CONSTRAINT chk_cliente_prueba CHECK (duracion_prueba_dias BETWEEN 1 AND 60),
    CONSTRAINT fk_cliente_campania FOREIGN KEY (id_campania)
        REFERENCES campania_marketing (id_campania)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_cliente_usuario_asignado FOREIGN KEY (id_usuario_asignado)
        REFERENCES usuario_sistema (id_usuario)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

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

CREATE TABLE IF NOT EXISTS propuesta (
    id_propuesta INT NOT NULL AUTO_INCREMENT,
    id_cliente INT NOT NULL,
    id_usuario INT NOT NULL,
    monto_estimado DECIMAL(14, 2),
    estado_propuesta VARCHAR(20) NOT NULL DEFAULT 'borrador',
    fecha_creacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_propuesta),
    KEY idx_propuesta_cliente (id_cliente),
    KEY idx_propuesta_usuario (id_usuario),
    KEY idx_propuesta_estado (estado_propuesta),
    CONSTRAINT chk_propuesta_monto CHECK (monto_estimado IS NULL OR monto_estimado >= 0),
    CONSTRAINT chk_propuesta_estado CHECK (
        estado_propuesta IN ('borrador', 'enviada', 'aceptada', 'rechazada')
    ),
    CONSTRAINT fk_propuesta_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente_prospecto (id_cliente) ON DELETE RESTRICT,
    CONSTRAINT fk_propuesta_usuario FOREIGN KEY (id_usuario)
        REFERENCES usuario_sistema (id_usuario) ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS actividad_web (
    id_actividad BIGINT NOT NULL AUTO_INCREMENT,
    id_cliente INT,
    visitor_id CHAR(36),
    url_visitada VARCHAR(500),
    fecha_actividad TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    tipo_evento VARCHAR(40),
    ip_origen VARCHAR(45),
    PRIMARY KEY (id_actividad),
    KEY idx_actividad_cliente_fecha (id_cliente, fecha_actividad),
    KEY idx_actividad_visitante_fecha (visitor_id, fecha_actividad),
    CONSTRAINT fk_actividad_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente_prospecto (id_cliente) ON DELETE RESTRICT
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

CREATE TABLE IF NOT EXISTS venta (
    id_venta INT NOT NULL AUTO_INCREMENT,
    id_propuesta INT NOT NULL,
    id_usuario INT NOT NULL,
    monto_final DECIMAL(14, 2) NOT NULL,
    fecha_cierre TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    metodo_pago VARCHAR(40),
    PRIMARY KEY (id_venta),
    UNIQUE KEY uq_venta_propuesta (id_propuesta),
    KEY idx_venta_usuario (id_usuario),
    KEY idx_venta_fecha (fecha_cierre),
    CONSTRAINT chk_venta_monto CHECK (monto_final > 0),
    CONSTRAINT fk_venta_propuesta FOREIGN KEY (id_propuesta)
        REFERENCES propuesta (id_propuesta) ON DELETE RESTRICT,
    CONSTRAINT fk_venta_usuario FOREIGN KEY (id_usuario)
        REFERENCES usuario_sistema (id_usuario) ON DELETE RESTRICT
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

DROP TRIGGER IF EXISTS trg_actualizar_prospecto;
DELIMITER $$
CREATE TRIGGER trg_actualizar_prospecto
AFTER UPDATE ON propuesta
FOR EACH ROW
BEGIN
    IF NEW.estado_propuesta IN ('enviada', 'aceptada')
       AND OLD.estado_propuesta <> NEW.estado_propuesta THEN
        UPDATE cliente_prospecto
           SET estado_prospecto = 'calificado'
         WHERE id_cliente = NEW.id_cliente
           AND estado_prospecto = 'nuevo';
    END IF;
END$$
DELIMITER ;

DROP PROCEDURE IF EXISTS sp_registrar_prospecto;
DELIMITER $$
CREATE PROCEDURE sp_registrar_prospecto(
    IN p_correo VARCHAR(150),
    IN p_nombre VARCHAR(120),
    IN p_empresa VARCHAR(120),
    IN p_ip VARCHAR(45),
    IN p_id_campania INT,
    OUT p_id_cliente INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
    INSERT INTO cliente_prospecto
        (correo_electronico, nombre, empresa, estado_prospecto, duracion_prueba_dias, id_campania)
    VALUES
        (LOWER(TRIM(p_correo)), p_nombre, p_empresa, 'nuevo', 60, p_id_campania);

    SET p_id_cliente = LAST_INSERT_ID();

    INSERT INTO actividad_web (id_cliente, url_visitada, tipo_evento, ip_origen)
    VALUES (p_id_cliente, '/descarga-prueba', 'descarga_prueba', p_ip);

    UPDATE cliente_prospecto
       SET puntaje_interes = 10
     WHERE id_cliente = p_id_cliente;
    COMMIT;
END$$
DELIMITER ;

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

DROP PROCEDURE IF EXISTS sp_reporte_mensual_ventas;
DELIMITER $$
CREATE PROCEDURE sp_reporte_mensual_ventas(IN p_mes INT, IN p_anio INT)
BEGIN
    DECLARE v_inicio DATE;

    IF p_mes < 1 OR p_mes > 12 OR p_anio < 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El mes o el año no son válidos.';
    END IF;

    SET v_inicio = STR_TO_DATE(
        CONCAT(p_anio, '-', LPAD(p_mes, 2, '0'), '-01'),
        '%Y-%m-%d'
    );

    SELECT u.nombre AS vendedor,
           COUNT(v.id_venta) AS cantidad_ventas,
           SUM(v.monto_final) AS ingreso_total
      FROM usuario_sistema AS u
      JOIN venta AS v ON v.id_usuario = u.id_usuario
     WHERE v.fecha_cierre >= v_inicio
       AND v.fecha_cierre < DATE_ADD(v_inicio, INTERVAL 1 MONTH)
     GROUP BY u.id_usuario, u.nombre
     ORDER BY SUM(v.monto_final) DESC;
END$$
DELIMITER ;

CREATE OR REPLACE VIEW v_tasa_conversion AS
SELECT c.id_campania,
       c.nombre_campania,
       COUNT(DISTINCT cp.id_cliente) AS total_prospectos,
       COUNT(DISTINCT v.id_venta) AS total_ventas,
       ROUND(
           100.0 * COUNT(DISTINCT v.id_venta)
           / NULLIF(COUNT(DISTINCT cp.id_cliente), 0),
           2
       ) AS tasa_conversion_pct
  FROM campania_marketing AS c
  LEFT JOIN cliente_prospecto AS cp ON cp.id_campania = c.id_campania
  LEFT JOIN propuesta AS p ON p.id_cliente = cp.id_cliente
  LEFT JOIN venta AS v ON v.id_propuesta = p.id_propuesta
 GROUP BY c.id_campania, c.nombre_campania;

CREATE OR REPLACE VIEW v_reporte_mensual_ventas AS
SELECT u.nombre AS vendedor,
       COUNT(v.id_venta) AS cantidad_ventas,
       SUM(v.monto_final) AS ingreso_total
  FROM usuario_sistema AS u
  JOIN venta AS v ON v.id_usuario = u.id_usuario
 WHERE v.fecha_cierre >= CAST(DATE_FORMAT(CURRENT_DATE(), '%Y-%m-01') AS DATE)
   AND v.fecha_cierre < DATE_ADD(
       CAST(DATE_FORMAT(CURRENT_DATE(), '%Y-%m-01') AS DATE),
       INTERVAL 1 MONTH
   )
 GROUP BY u.id_usuario, u.nombre;
