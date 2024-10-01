#!/bin/bash

# 모니터링할 디렉토리 설정
WATCH_DIR="/home/username/jenkins/appjardir"
JAR_FILE="SpringApp-0.0.1-SNAPSHOT.jar"
LOCK_FILE="/tmp/deploy.lock"
DEPLOY_FILE="/home/username/jenkins/appjardir/SpringApp-0.0.1-SNAPSHOT.jar"
VM2_USER="username"
VM2_IP="10.0.2.19"
VM2_PATH="/home/username/deploy"
LOG_FILE="/home/username/jenkins/log/deploy_script.log"  # 로그 파일 경로 (필요 시 변경)

# 로그 함수
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# 잠금 파일 체크 함수
check_lock() {
  if [ -f "$LOCK_FILE" ]; then
    log "이미 배포 작업이 진행 중입니다. 새 이벤트를 무시합니다."
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
inotifywait -m -e close_write --format '%f' "$WATCH_DIR" | while read -r FILENAME
do
  # 특정 파일의 변경 감지
  if [[ "$FILENAME" == "$JAR_FILE" ]]; then
    check_lock
    create_lock

    log "변경된 JAR 파일 감지: $FILENAME"

    # JAR 파일을 VM2로 전송
    scp "$DEPLOY_FILE" "$VM2_USER@$VM2_IP:$VM2_PATH"
    if [ $? -eq 0 ]; then
      log "JAR 파일을 VM2로 성공적으로 전송했습니다: $DEPLOY_FILE -> $VM2_USER@$VM2_IP:$VM2_PATH"
    else
      log "JAR 파일 전송에 실패했습니다: $DEPLOY_FILE -> $VM2_USER@$VM2_IP:$VM2_PATH"
      remove_lock
      continue  # 전송 실패 시 다음 이벤트를 기다림
    fi

    remove_lock
  fi
done
