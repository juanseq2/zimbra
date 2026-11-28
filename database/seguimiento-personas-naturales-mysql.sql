-- Amplía las solicitudes de personas naturales con empresa, prospecto y seguimiento.
-- Ejecutar una sola vez después de autenticacion-usuarios-mysql.sql.

ALTER TABLE cliente_persona_natural
    ADD COLUMN empresa VARCHAR(120) NULL AFTER nombre,
    ADD COLUMN id_cliente_prospecto INT NULL AFTER empresa,
    ADD UNIQUE KEY uq_persona_prospecto (id_cliente_prospecto),
    ADD CONSTRAINT fk_persona_prospecto FOREIGN KEY (id_cliente_prospecto)
        REFERENCES cliente_prospecto (id_cliente) ON DELETE RESTRICT;

ALTER TABLE cliente_persona_natural
    DROP CHECK chk_persona_estado,
    ADD CONSTRAINT chk_persona_estado CHECK (
        estado_solicitud IN (
            'pendiente', 'en_revision', 'contactada', 'propuesta_enviada',
            'pendiente_pago', 'activada', 'rechazada', 'archivada'
        )
    );

CREATE TABLE IF NOT EXISTS persona_natural_historial (
    id_historial BIGINT NOT NULL AUTO_INCREMENT,
    id_persona INT NOT NULL,
    estado VARCHAR(30) NOT NULL,
    detalle VARCHAR(500) NOT NULL,
    id_usuario INT NULL,
    creado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_historial),
    KEY idx_persona_historial_fecha (id_persona, creado_en),
    CONSTRAINT fk_historial_persona FOREIGN KEY (id_persona)
        REFERENCES cliente_persona_natural (id_persona) ON DELETE CASCADE,
    CONSTRAINT fk_historial_usuario FOREIGN KEY (id_usuario)
        REFERENCES usuario_sistema (id_usuario) ON DELETE SET NULL
) ENGINE=InnoDB;

INSERT INTO cliente_prospecto
    (correo_electronico, nombre, estado_prospecto, duracion_prueba_dias)
SELECT p.correo_electronico, p.nombre, 'nuevo', 60
  FROM cliente_persona_natural AS p
  LEFT JOIN cliente_prospecto AS cp
    ON cp.correo_electronico = p.correo_electronico
 WHERE cp.id_cliente IS NULL;

UPDATE cliente_persona_natural AS p
JOIN cliente_prospecto AS cp
  ON cp.correo_electronico = p.correo_electronico
   SET p.id_cliente_prospecto = cp.id_cliente,
       p.empresa = COALESCE(p.empresa, cp.empresa);

INSERT INTO persona_natural_historial (id_persona, estado, detalle)
SELECT p.id_persona, p.estado_solicitud,
       CONCAT('Estado actual de la solicitud: ', p.estado_solicitud)
  FROM cliente_persona_natural AS p
 WHERE NOT EXISTS (
    SELECT 1
      FROM persona_natural_historial AS h
     WHERE h.id_persona = p.id_persona
 );
