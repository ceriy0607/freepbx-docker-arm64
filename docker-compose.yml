version: '3.8'

services:
  freepbx:
    build: .
    container_name: freepbx-arm64
    ports:
      - "80:80"
      - "443:443"
      - "5060:5060/udp"
      - "5061:5061/udp"
      - "3306:3306"
    volumes:
      - asterisk-data:/etc/asterisk
    restart: always
    tty: true

volumes:
  asterisk-data:
