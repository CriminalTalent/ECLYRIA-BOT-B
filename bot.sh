#!/bin/bash

BOT_DIR="/root/ECLYRIA-BOT-B"
PID_FILE="$BOT_DIR/bot.pid"
LOG_DIR="$BOT_DIR/logs"
LOG_FILE="$LOG_DIR/bot.log"

mkdir -p "$LOG_DIR"

cd "$BOT_DIR"

case "$1" in
  start)
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
      echo "봇이 이미 실행 중입니다. (PID: $(cat $PID_FILE))"
    else
      nohup bundle exec ruby main.rb >> "$LOG_FILE" 2>&1 &
      echo $! > "$PID_FILE"
      echo "봇 시작됨 (PID: $!)"
    fi
    ;;
  stop)
    if [ -f "$PID_FILE" ]; then
      PID=$(cat "$PID_FILE")
      if kill -0 "$PID" 2>/dev/null; then
        kill -9 "$PID"
        rm "$PID_FILE"
        echo "봇 종료됨 (PID: $PID)"
      else
        rm "$PID_FILE"
        echo "봇이 실행 중이 아닙니다."
      fi
    else
      echo "PID 파일이 없습니다."
    fi
    ;;
  restart)
    $0 stop
    sleep 1
    $0 start
    ;;
  status)
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
      echo "봇 실행 중 (PID: $(cat $PID_FILE))"
    else
      echo "봇 중지됨"
    fi
    ;;
  log)
    tail -f "$LOG_FILE"
    ;;
  *)
    echo "사용법: $0 {start|stop|restart|status|log}"
    exit 1
    ;;
esac
