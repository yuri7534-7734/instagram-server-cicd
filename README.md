# instagram-server

Spring Boot 기반의 Instagram 백엔드 서버. **GitHub Actions → GHCR → AWS Lightsail**까지 이어지는 완전 자동화된 CI/CD 파이프라인이 구축되어 있다. `git push` 한 번으로 약 2~3분 내에 프로덕션 서버까지 새 버전이 배포된다.

> 🚀 **라이브 데모**: http://3.34.51.118:8080/ → `Hello, World!`
>
> 도메인 코드는 아직 Hello World 수준이지만, **인프라/배포 파이프라인은 production-ready** 상태.

## 기술 스택

| 영역 | 내용 |
|---|---|
| 언어 / 런타임 | Java 17 (Eclipse Temurin) |
| 프레임워크 | Spring Boot 3.5.14 |
| 빌드 도구 | Gradle (wrapper 포함) |
| 데이터베이스 | MySQL 8 |
| ORM | Spring Data JPA (Hibernate) |
| 컨테이너 | Docker / Docker Compose |
| 이미지 레지스트리 | GitHub Container Registry (GHCR) |
| CI/CD | GitHub Actions |
| 호스팅 | AWS Lightsail (Ubuntu 22.04, 도쿄 리전) |

## 프로젝트 구조

```
instagram-server/
├── .github/workflows/
│   └── main.yml                          # CI/CD 워크플로 (build → GHCR push → 배포)
├── src/main/java/com/example/instagram_server/
│   ├── InstagramServerApplication.java   # 엔트리 포인트
│   └── AppController.java                # GET / → "Hello, World!"
├── src/main/resources/
│   └── application.yml                   # Spring 설정 (DB 등)
├── build.gradle                          # Gradle 빌드 스크립트
├── settings.gradle
├── Dockerfile                            # 서버 컨테이너 이미지 빌드
├── compose.yml                           # GHCR 이미지 pull (로컬/Lightsail 공용)
└── .gitignore
```

## CI/CD 아키텍처

```
   로컬 PC          GitHub Actions          GHCR              AWS Lightsail
  ─────────       ──────────────────     ─────────         ──────────────────
   git push   →    JDK 셋업              docker push   →    docker compose pull
                  ./gradlew build       (latest +          docker compose up -d
                  docker build           git-<sha>)
                                                            ↓
                                                          http://3.34.51.118:8080/
```

핵심: **로컬에서 빌드/푸시할 필요 없음.** `git push origin main` 하면 약 2~3분 뒤 프로덕션이 갱신된다.

## 빠른 시작 (로컬 개발)

### 옵션 1: `./gradlew bootRun` (활발한 개발 시)

코드 수정 → 즉시 재기동이 가능한 가장 빠른 사이클. 호스트에 MySQL 8이 직접 설치돼 있고 `mydb` 데이터베이스가 생성돼 있어야 한다.

```bash
./gradlew bootRun
```

> ⚠️ [application.yml:3](src/main/resources/application.yml#L3)의 DB host가 `my-db`(컴포즈 서비스명)로 설정돼 있다. 호스트에서 직접 실행하려면 `localhost`로 바꾸거나 OS의 hosts 파일에 `127.0.0.1 my-db`를 추가해야 연결된다.

### 옵션 2: Docker Compose로 GHCR 이미지 실행 (prod-like 검증)

GitHub Actions가 GHCR에 올린 **최신 이미지**를 그대로 받아서 실행. 본인 코드 변경분은 `git push` → CI 빌드 완료 후에야 반영된다.

```bash
docker compose pull
docker compose up -d
```

- 서버: `http://localhost:8080`
- MySQL: 호스트 포트 `3307` → 컨테이너 `3306`

> 로컬 빌드 이미지로 즉시 테스트하려면:
> `./gradlew build && docker build -t ghcr.io/nissi153/instagram-server:latest . && docker compose up -d`

## API

| Method | Path | 설명 |
|---|---|---|
| GET | `/` | `"Hello, World!"` 반환 |

## GitHub Actions CI/CD

워크플로 파일: [.github/workflows/main.yml](.github/workflows/main.yml)

### 트리거

- `push` → `main` 브랜치
- `workflow_dispatch` (Actions 탭에서 수동 실행)

### Job 1: `build-and-push` (항상 실행)

| 단계 | 설명 |
|---|---|
| 1 | `actions/checkout@v4` |
| 2 | JDK 17 (Temurin) 셋업 |
| 3 | Gradle 셋업 + 의존성/래퍼 캐시 자동 활성화 |
| 4 | `./gradlew clean build` (테스트 포함) |
| 5 | `GITHUB_TOKEN`으로 GHCR 로그인 (**PAT 불필요**) |
| 6 | Docker Buildx 셋업 + GHA 레이어 캐시 |
| 7 | `docker/metadata-action`으로 태그 자동 부여 |
| 8 | `docker build` & `push` |

### 이미지 태그 전략

| 태그 | 용도 |
|---|---|
| `:latest` | 롤링 — `compose.yml`이 참조하는 기본 태그 (default branch에서만 부여) |
| `:git-<sha>` | 불변 — 특정 커밋으로 롤백할 때 사용 |

예: `ghcr.io/nissi153/instagram-server:git-c8f123e`

### Job 2: `deploy` (자동 배포)

`build-and-push` 성공 + **`vars.DEPLOY_ENABLED == 'true'`** 일 때만 실행. SSH로 Lightsail에 접속해:

```bash
docker compose pull
docker compose up -d
docker image prune -f
```

### CI/CD 활성화 — 필수 설정 정리

GitHub 저장소 → **Settings → Secrets and variables → Actions**에서 등록.

#### Variables (1개)

| 이름 | 값 |
|---|---|
| `DEPLOY_ENABLED` | `true` |

#### Secrets (4개)

| 이름 | 값 |
|---|---|
| `LIGHTSAIL_HOST` | Lightsail 퍼블릭 IP (예: `3.34.51.118`) |
| `LIGHTSAIL_USER` | `ubuntu` |
| `LIGHTSAIL_SSH_KEY` | `LightsailDefaultKey.pem` 전체 내용 (`-----BEGIN ... END-----` 포함) |
| `LIGHTSAIL_PROJECT_PATH` | `compose.yml`이 있는 디렉토리 (예: `/home/ubuntu/instagram-server`) |

> **SSH 키 등록 팁**: `cat LightsailDefaultKey.pem`으로 출력한 텍스트를 줄바꿈 그대로 붙여넣기.

#### GHCR 패키지 권한 (한 번만)

처음 로컬 PAT로 GHCR에 푸시한 패키지는 **user-owned** 상태라 GHA의 `GITHUB_TOKEN`이 push 권한을 못 가진다. 다음 중 하나로 해결:

- **권장**: GitHub → 본인 프로필 → Packages → `instagram-server` → Package settings → **Manage Actions access** → Add Repository → `instagram-server-0427` (Write 권한)
- 또는: 패키지 삭제 후 GHA가 새로 생성하게 하기 (저장소 소속으로 자동 생성됨)

### 롤백

```bash
# Lightsail에서
cd /home/ubuntu/instagram-server

# 이전 커밋 sha로 태그 강제 적용
docker pull ghcr.io/nissi153/instagram-server:git-789e757
docker tag  ghcr.io/nissi153/instagram-server:git-789e757 \
            ghcr.io/nissi153/instagram-server:latest
docker compose up -d
```

## AWS Lightsail 초기 셋업 (한 번만)

자동 배포 대상 서버를 처음 만드는 절차. 이미 셋업된 경우 건너뛴다.

### 1. 인스턴스 & 방화벽

- Lightsail 콘솔 → **Ubuntu 22.04** 인스턴스 생성
- **Networking** 탭 → **Port 8080 (TCP)** 인바운드 규칙 추가

### 2. SSH 접속 & 시스템 업데이트

```bash
ssh -i LightsailDefaultKey.pem ubuntu@<퍼블릭_IP>
sudo apt update && sudo apt upgrade -y
```

### 3. Docker + Compose 설치

```bash
sudo apt install -y ca-certificates curl gnupg lsb-release
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker $USER
newgrp docker

docker --version && docker compose version
```

### 4. 프로젝트 디렉토리 & compose.yml

```bash
mkdir -p ~/instagram-server && cd ~/instagram-server
# 레포의 compose.yml 내용을 그대로 복사 (예: nano compose.yml)
```

### 5. GHCR 패키지 가시성

처음 푸시한 패키지는 **private**. 다음 중 선택:

- **Public으로 변경** → Lightsail에서 인증 없이 pull (간편)
  GitHub → Packages → `instagram-server` → Package settings → Change visibility → Public
- **Private 유지** → Lightsail에 read-only PAT로 GHCR 로그인:
  ```bash
  echo $CR_PAT | docker login ghcr.io -u nissi153 --password-stdin
  ```

### 6. 첫 배포 (수동 한 번)

GHA가 GHCR에 이미지를 올린 뒤, Lightsail에서 한 번 직접 pull/up:

```bash
docker compose pull
docker compose up -d
curl http://localhost:8080/    # → Hello, World!
```

이후부터는 GHA의 `deploy` job이 알아서 처리.

## 운영 명령어 (Lightsail)

```bash
# 상태 확인
docker compose ps
docker compose logs -f my-server

# 재시작
docker compose restart

# 중지
docker compose down

# DB 데이터까지 모두 제거 (주의!)
docker compose down -v && rm -rf mysql_data

# 사용하지 않는 옛 이미지 정리 (deploy job이 자동으로 함)
docker image prune -f
```

## 수동 배포 (GHA 없이) — 백업 경로

GitHub Actions가 막혔을 때 대비.

### A. 로컬 PC에서 GHCR 푸시

```bash
# 1) PAT 발급: GitHub Settings → Developer settings → PATs (classic)
#    권한: write:packages, read:packages
# 2) 빌드 & 푸시
./gradlew clean build -x test
echo $CR_PAT | docker login ghcr.io -u nissi153 --password-stdin
docker build -t ghcr.io/nissi153/instagram-server:latest .
docker push ghcr.io/nissi153/instagram-server:latest
```

### B. Lightsail에서 재기동

```bash
cd ~/instagram-server
docker compose pull
docker compose up -d
```

## 트러블슈팅 — 이번에 만난 함정들

CI/CD를 처음 구축하면서 부딪힌 문제들과 해결법. 같은 상황 재발 시 참고용.

### 1. `compose-local.yml`에 DB 연결 환경변수가 없어서 connection refused

**증상**: 컨테이너가 `localhost:3306`으로 연결 시도 → 컨테이너 자기 자신을 가리켜 실패.

**해결**: `my-server` 서비스에 `SPRING_DATASOURCE_URL: jdbc:mysql://my-db:3306/mydb` 환경변수 추가. 또는 `application.yml`의 host를 `my-db`(컴포즈 서비스명)로 직접 명시.

### 2. 한글 브랜치명 → GitHub Actions 미트리거

**증상**: `mydb연결` 브랜치에 push했는데 워크플로 안 돎.

**원인**: 워크플로 트리거가 `branches: [main]`으로 명시돼 있는데 push는 다른 브랜치에 일어남. `workflow_dispatch`도 default branch(main)에 워크플로 파일이 없으면 실행 불가.

**해결**: 영문 브랜치명으로 rename 후 PR로 main에 머지.
```bash
git branch -m mydb연결 feat/mydb-connection
git push origin -u feat/mydb-connection
git push origin --delete mydb연결
```

### 3. `./gradlew: Permission denied` (exit 126)

**증상**: GHA Linux 러너에서 `./gradlew clean build` 단계가 즉시 실패.

**원인**: Windows에서 commit한 `gradlew`에 Unix execute bit이 없음. NTFS는 execute bit 개념이 없어서 git이 mode `100644`로 저장.

**해결**: git index에서만 mode를 변경. Windows 로컬 파일은 그대로 두고 commit.
```bash
git update-index --chmod=+x gradlew
git commit -m "Make gradlew executable"
git push
```

### 4. `denied: permission_denied: write_package` (GHCR push 실패)

**증상**: `Build with Gradle`은 성공, `Build and push Docker image`에서 push 단계가 실패.

**원인**: 이미지를 처음 로컬 PAT로 push했을 때 패키지가 **user-owned**로 생성됨 → 어떤 저장소와도 연결되지 않은 상태 → GHA의 `GITHUB_TOKEN`은 저장소 소속이라 user-owned 패키지에 write 권한 없음.

**해결**: 패키지를 저장소에 연결.
- GitHub → 프로필 → Packages → `instagram-server` → Package settings
- **Manage Actions access** → Add Repository → `instagram-server-0427` (Write)

대안: 패키지 삭제 후 GHA가 새로 생성하게 두면 자동으로 저장소 소속이 됨.

### 5. `<GITHUB_USERNAME>` placeholder를 그대로 commit

**증상**: `compose.yml`의 `image: ghcr.io/<GITHUB_USERNAME>/...`을 안 바꾸고 push → Lightsail에서 `pull access denied` 에러.

**해결**: 본인 GitHub 사용자명(소문자)으로 직접 치환. `<>` 같은 placeholder는 사람이 읽기 쉽지만 컴퓨터는 그대로 해석함.

## 데이터베이스 설정

[application.yml](src/main/resources/application.yml) 기본값:

```yaml
url: jdbc:mysql://my-db:3306/mydb     # docker compose 내부 서비스명 기준
username: root
password: pwd1234
ddl-auto: update
```

[compose.yml](compose.yml)에서 `SPRING_DATASOURCE_URL` 환경변수로 덮어쓰기 가능.

## 알려진 이슈 / 개선 포인트

### 🟡 권장 — 실서비스 전 정리 필요

1. **자격증명 하드코딩** — `application.yml`, `compose.yml`의 `pwd1234`를 `.env` + `${VAR}` 치환으로 분리. GitHub Secrets로 옮기고 `compose.yml`에서 `${MYSQL_ROOT_PASSWORD}` 형태로 참조.
2. **JPA `ddl-auto: update`** — 운영에서는 `validate`로 변경. 환경별 프로파일 분리 (`application-prod.yml`).
3. **Multi-stage Dockerfile** — 현재 [Dockerfile](Dockerfile)은 호스트에서 미리 만든 jar를 복사하는 방식이라 빌드 단계에 JDK 필요. 멀티스테이지로 바꾸면 GHA 워크플로에서 `gradlew build` 단계를 제거하고 `docker build` 한 번으로 끝낼 수 있음.
4. **패키지 구조 분리** — 도메인이 커지기 전에 `controller/`, `service/`, `repository/`, `entity/`, `dto/`로 정리.
5. **테스트 코드 부재** — `src/test/`가 비어 있음. 최소 컨텍스트 로딩 테스트라도 추가하면 CI 파이프라인이 의미를 가짐.

### ⚪ 운영 강화 (선택)

- **HTTPS** — Caddy/Nginx + Let's Encrypt, 또는 Lightsail 로드밸런서
- **도메인 연결** — IP 직접 노출 대신 도메인 사용
- **DB 백업** — Lightsail 스냅샷 정기 생성
- **헬스체크 / 모니터링** — UptimeRobot 같은 외부 watchdog
- **swap 메모리** — Lightsail 1GB 인스턴스에서 MySQL OOM 방지
  ```bash
  sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
  sudo mkswap /swapfile && sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  ```
- **UFW 방화벽** — `sudo ufw allow OpenSSH && sudo ufw allow 8080/tcp && sudo ufw enable`

### 🔵 CI/CD 강화 (선택)

- **PR 빌드 검증** — `pull_request` 트리거로 main 머지 전에 build 검증
- **Slack/Discord 알림** — 배포 성공/실패 통지
- **Staging 환경** — `develop` 브랜치 → staging Lightsail / `main` → prod 분리

## 다음 단계 로드맵 (도메인 구현)

이름은 instagram-server인데 아직 인스타그램 기능은 없는 상태. 인프라 위에 도메인을 쌓아갈 차례.

| 단계 | 작업 |
|---|---|
| 1 | 패키지 구조 분리 (`controller/service/repository/entity/dto`) |
| 2 | `User` 엔티티 + 회원가입/조회 API → JPA 동작 검증 |
| 3 | `Post` 도메인 — 게시글 CRUD |
| 4 | Spring Security + JWT 인증/인가 |
| 5 | 이미지 업로드 — S3 연동 (Lightsail에 IAM role) |
| 6 | `Follow` 다대다 매핑 |
| 7 | 피드 조회 (팔로우 + 페이지네이션) |
| 8 | 댓글 / 좋아요 |

각 단계마다 push → 2~3분 뒤 prod 자동 배포되는 사이클을 그대로 활용 가능.

## .gitignore 주요 항목

- 빌드 산출물: `.gradle`, `build/`, `bin/`, `out/`
- IDE: `.idea`, `.vscode/`, `*.iml`, `.classpath`, `.project`
- 로컬 DB 데이터: `mysql_data/`
- 비밀값: `.env`, `.env.*` (단, `.env.example`은 허용)
- 로그: `*.log`, `logs/`

## 라이선스

미정
