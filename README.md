# GNS3 Installer — Debian 

> by **k1k04**

---

## Instalación

```bash
chmod +x install_gns3_debian13.sh
./install_gns3_debian13.sh
```

Cuando termine, **cierra sesión y vuelve a entrar** para aplicar los grupos (`kvm`, `libvirt`, `wireshark`).

---

## Abrir GNS3

```bash
gns3-launcher
```

O si prefieres activar el venv manualmente:

```bash
source ~/gns3-venv/bin/activate
gns3
```

---

## Imágenes de dispositivos

| Tipo | Ruta |
|---|---|
| Cisco IOS (Dynamips) | `~/GNS3/images/IOS/` |
| QEMU (IOSv, ASAv...) | `~/GNS3/images/QEMU/` |

---

*Testeado en Debian 13 Trixie — GNS3 v3.x — PyQt6*
