#!/bin/bash

# ==========================================
# monitor.sh
# Monitorea CPU, MEM y RSS de un proceso
# y genera una gráfica al finalizar.
# Uso:
#   ./monitor.sh "comando" [intervalo]
# Ejemplo:
#   ./monitor.sh "stress --cpu 2 --timeout 30" 1
# ==========================================

set -u

# ---------- Validación de argumentos ----------
if [ $# -lt 1 ]; then
    echo "Uso: $0 \"comando\" [intervalo_segundos]"
    exit 1
fi

COMANDO="$1"
INTERVALO="${2:-2}"

# Validar que el intervalo sea numérico y mayor que 0
if ! [[ "$INTERVALO" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "Error: el intervalo debe ser un número positivo."
    exit 1
fi

# ---------- Verificar dependencias ----------
if ! command -v gnuplot >/dev/null 2>&1; then
    echo "Error: gnuplot no está instalado."
    echo "Instálalo con: sudo apt update && sudo apt install gnuplot"
    exit 1
fi

# ---------- Variables globales ----------
PID=""
LOGFILE=""
DATAFILE=""
PNGFILE=""
GNUPLOT_SCRIPT=""
START_EPOCH=0
TERMINADO_POR_USUARIO=0

# ---------- Limpieza de temporales ----------
cleanup_temp() {
    [ -n "${DATAFILE:-}" ] && [ -f "$DATAFILE" ] && rm -f "$DATAFILE"
    [ -n "${GNUPLOT_SCRIPT:-}" ] && [ -f "$GNUPLOT_SCRIPT" ] && rm -f "$GNUPLOT_SCRIPT"
}

# ---------- Graficación ----------
graficar() {
    if [ ! -f "$LOGFILE" ]; then
        echo "No se encontró el log para graficar."
        return
    fi

    # Convertir log a formato: segundos cpu mem rss
    awk -v inicio="$START_EPOCH" '
    {
        fecha=$1
        hora=$2
        cpu=$3
        mem=$4
        rss=$5
        cmd="date -d \"" fecha " " hora "\" +%s"
        cmd | getline epoch
        close(cmd)
        tiempo=epoch-inicio
        print tiempo, cpu, mem, rss
    }' "$LOGFILE" > "$DATAFILE"

    if [ ! -s "$DATAFILE" ]; then
        echo "No hay datos para graficar."
        return
    fi

    cat > "$GNUPLOT_SCRIPT" <<EOF
set terminal pngcairo size 1200,700
set output "$PNGFILE"
set title "Monitoreo: $COMANDO (PID $PID)"
set xlabel "Tiempo transcurrido (s)"
set ylabel "CPU (%)"
set y2label "Memoria RSS (KB)"
set y2tics
set grid
set key outside
plot "$DATAFILE" using 1:2 with lines title "CPU (%)" axes x1y1, \
     "$DATAFILE" using 1:4 with lines title "RSS (KB)" axes x1y2
EOF

    gnuplot "$GNUPLOT_SCRIPT"
    echo "Gráfica generada: $PNGFILE"
}

# ---------- Manejo de Ctrl+C ----------
manejar_sigint() {
    echo
    echo "Interrupción detectada. Enviando SIGTERM al proceso monitoreado..."
    TERMINADO_POR_USUARIO=1

    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill -TERM "$PID" 2>/dev/null
        wait "$PID" 2>/dev/null
    fi

    graficar
    cleanup_temp
    exit 0
}

trap manejar_sigint SIGINT

# ---------- Lanzar proceso ----------
bash -c "$COMANDO" &
PID=$!

LOGFILE="monitor_${PID}.log"
DATAFILE="$(mktemp)"
GNUPLOT_SCRIPT="$(mktemp)"
PNGFILE="monitor_${PID}.png"
START_EPOCH=$(date +%s)

echo "Proceso lanzado."
echo "Comando : $COMANDO"
echo "PID     : $PID"
echo "Intervalo: $INTERVALO s"
echo "Log     : $LOGFILE"
echo "Imagen  : $PNGFILE"

# ---------- Monitoreo periódico ----------
while kill -0 "$PID" 2>/dev/null; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    # Extraer cpu, mem y rss sin encabezados
    read -r CPU MEM RSS <<< "$(ps -p "$PID" -o %cpu,%mem,rss --no-headers 2>/dev/null | awk '{print $1, $2, $3}')"

    # Si ps no devolvió datos, salir del ciclo
    if [ -z "${CPU:-}" ] || [ -z "${MEM:-}" ] || [ -z "${RSS:-}" ]; then
        break
    fi

    echo "$TIMESTAMP $CPU $MEM $RSS" >> "$LOGFILE"
    sleep "$INTERVALO"
done

# Esperar al proceso si todavía queda algo por recolectar
wait "$PID" 2>/dev/null

# ---------- Graficar al final ----------
graficar
cleanup_temp

if [ "$TERMINADO_POR_USUARIO" -eq 0 ]; then
    echo "Monitoreo finalizado porque el proceso terminó."
fi
