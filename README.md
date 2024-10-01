# 🏊‍♂️ Git Webhook Jenkins CI/CD Pipline 구축하기

## ✅ 개요
> 애플리케이션을 개발단계부터 배포단계까지 자동화하여 좀 더 빠르고 효율적이게 사용자에게 빈번히 배포할 수 있게 하는 것을 목표로합니다. 테스트 서버에서 빌드와 테스트가 진행되고 jar 파일을 운영서버로 옮겨 더욱 안정적인 환경에서 서비스될 수 있도록 합니다.

<br>

## 🕍 CI/CD Workflow
**1. VM1은 테스트 서버, VM2는 운영서버입니다.**<br>
**2. Git push를하면 jenkins 파이프라인이 실행되면서 jar가 빌드됩니다.**<br>
**3. 빌드된 jar는 VM1 -> VM2로 SCP 프로토콜을 통해 공유됩니다.**<br>
**4. inotify-tools 라이브러리를 통해 VM2에서 jar 파일의 변경이 감지되면 새로운 버전을 배포합니다.**

<br>

## 1️⃣ 젠킨스 파이프라인 스크립트 작성
```yaml
pipeline {
    agent any

    stages {
        stage('Clone Repository') {
            steps {
                git branch: 'main', url: 'https://github.com/ChoiYoungHa/Jenkins-Test.git'
                echo "다운로드"
            }
        }
         stage('Build') {
            steps {
                sh 'chmod +x gradlew'                    
                sh './gradlew clean build -x test'
                sh 'echo $WORKSPACE'
            }
        }
        stage('Copy jar') { 
            steps {
                script {
                    def jarFile = 'build/libs/SpringApp-0.0.1-SNAPSHOT.jar'
                    def destDir = '/var/jenkins_home/appjar/'
                    def destFile = "${destDir}SpringApp-0.0.1-SNAPSHOT.jar"
                    def backupFile = "${destDir}SpringApp-0.0.1-SNAPSHOT.jar.bak"
                    
                    // 기존 jar 파일이 존재하는지 확인하고 백업
                    sh """
                        if [ -f "${destFile}" ]; then
                            mv "${destFile}" "${backupFile}"
                            echo "기존 jar 파일을 백업했습니다: ${backupFile}"
                        else
                            echo "백업할 기존 jar 파일이 없습니다."
                        fi
                    """
                    
                    // 새로운 jar 파일 복사
                    sh "cp ${jarFile} ${destDir}"
                    echo "새로운 jar 파일을 복사했습니다: ${destFile}"
                }
            }
        }
    }
}
```

<br>
1. git hook을 사용하여 등록된 레포지토리의 변경이 발생하면 젠킨스가 clone 합니다.<br>
2. 변경된 코드를 test, build 합니다.<br>
3. jar 파일을 마운트된 볼륨에 생성합니다.<br>
4. 이전버전을 백업하고 기존 jar 파일을 덮어 씌웁니다.<br>

 <br>

 ## 2️⃣ 젠킨스 파이프라인 테스트
![2024-10-01 17 38 51](https://github.com/user-attachments/assets/e396d06f-0fda-457f-ba18-057adffea552)
![2024-10-01 17 39 30](https://github.com/user-attachments/assets/9e01e8ba-7ebc-4d39-ba2c-1dcb8909718e)

**정상적으로 변경된 소스코드가 jar 파일로 빌드되었습니다.**

<br>

## 3️⃣ 젠킨스 빌드 후 VM2로 전송 쉘스크립트 작성

```shell
#!/bin/bash

# 모니터링할 디렉토리 설정
WATCH_DIR="/home/username/jenkins/appjardir"
JAR_FILE="SpringApp-0.0.1-SNAPSHOT.jar"
LOCK_FILE="/tmp/deploy.lock"
DEPLOY_FILE="/home/username/jenkins/appjardir/SpringApp-0.0.1-SNAPSHOT.jar"
VM2_USER="username"
VM2_IP="10.0.2.19"
VM2_PATH="/home/username/deploy"
LOG_FILE="/home/username/jenkins/log/deploy_script.log"
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
      continue
    fi

    remove_lock
  fi
done
```

**VM2 서버에 비밀번호를 일일이 입력할 필요 없이 파일을 전송하기 위해 ssh key를 생성하였습니다.**

 ```bash
# ssh key 생성
ssh-keygen -t rsa -b 4096

# 공개키 복사
ssh-copy-id username@10.0.2.19
 ```

 ## 4️⃣ 전송 쉘 스크립트 테스트

**VM1에서 Jenkins에서 build 완료 시 이를 감지하고 VM2 전송**
![2024-10-01 20 21 47](https://github.com/user-attachments/assets/5859091c-fba3-4a53-a6e0-15fe301c7d0f)
![2024-10-01 20 22 24](https://github.com/user-attachments/assets/bc881eaf-0610-4d6d-bf91-087fd0be6ac8)

> 10월1일 20시20분 빌드가 완료되어 inotify-tools 라이브러리가 이를 감지하여 SCP로 VM2에 jar 파일을 공유합니다.

<br>


## 5️⃣ VM2에서 jar 파일의 변경을 감지하고 재시작
**jar 파일 변경감지 후 재시작 스크립트**
```bash
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
      echo "$(date '+%Y-%m-%d %H:%M:%S') - 포트 8999을 사용 중인 프로세스 발견 PID: $PID"
      kill -9 "$PID"
      if [ $? -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - PID: $PID 프로세스 종료 성공"
      else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - PID: $PID 프로세스 종료 실패"
        remove_lock
        continue
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
```

**[실행결과]**
![2024-10-01 20 44 51](https://github.com/user-attachments/assets/fab027b3-0c3c-478b-a4db-4573688bd953)



## 💭결론 및 고찰
jenkins, webhook, shell script를 사용하여 CI/CD 파이프라인을 구축했습니다. git repository에 push만 한다면 빌드와 배포를 자동화하여 반복작업을 최소화할 수 있습니다. 해당 작업을 진행하면서 리눅스의 쉘스크립트를 응용하여 작성 해보고, jenkins 파이프라인 스크립트를 작성해보며 CI/CD에 대해 이해하고 탐구할 수 있었습니다.