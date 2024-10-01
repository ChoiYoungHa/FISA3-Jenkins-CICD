#!/bin/bash

# 모니터링할 디렉토리 설정
WATCH_DIR="/home/username/deploy"
JAR_FILE="SpringApp-0.0.1-SNAPSHOT.jar"
LOG_FILE="$WATCH_DIR/app.log"        # 애플리케이션 로그 파일
LOCK_FILE="/tmp/deploy.lock"          # 잠금 파일

# 잠금 파일 체크 함수
check_lock() {
  if [ -f "$LOCK_FILE" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 이미 배포 작업이 진행 중입니다. 새 이벤트를 무시합니다."
    exit 0
  fi
}

# 잠금 파일 생성 함수
create_lock() {
  touch "$LOCK_FILE"
}

# 잠금 파일 제거 함수
remove_lock() {
  rm -f "$LOCK_FILE"
}

# inotifywait를 사용하여 파일 쓰기 완료 감지
inotifywait -m -e close_write --format '%f' "$WATCH_DIR" | while read FILENAME
do
  # 특정 파일의 변경 감지
  if [[ "$FILENAME" == "$JAR_FILE" ]]; then
    check_lock
    create_lock

    echo "$(date '+%Y-%m-%d %H:%M:%S') - 변경된 JAR 파일 감지: $FILENAME"

    # 1. 포트 8999을 사용 중인 프로세스 찾기 및 종료
    PID=$(lsof -t -i :8999)
    if [ -n "$PID" ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') - 포트 8999을 사용 중인 프로세스 발견: PID $PID"
      kill -9 "$PID"
      if [ $? -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - PID $PID 프로세스 종료 성공"
      else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - PID $PID 프로세스 종료 실패"
        remove_lock
        continue  # 프로세스 종료에 실패하면 다음 단계로 진행하지 않음
      fi
    else
      echo "$(date '+%Y-%m-%d %H:%M:%S') - 포트 8999을 사용하는 프로세스가 없습니다."
    fi

    # 3. 새로운 JAR 파일 실행 (nohup 사용)
    nohup java -jar "$WATCH_DIR/$JAR_FILE" > "$LOG_FILE" 2>&1 &
    if [ $? -eq 0 ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') - 새로운 JAR 파일을 백그라운드에서 실행했습니다."
    else
      echo "$(date '+%Y-%m-%d %H:%M:%S') - 새로운 JAR 파일 실행 실패"
    fi

    # 잠금 파일 제거
    remove_lock
  fi
done
