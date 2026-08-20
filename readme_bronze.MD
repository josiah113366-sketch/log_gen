# 개요
- main 브랜치는 로그를 CloudWatch에 저장하고 있음
  - 어플리케이션 상태/오류/디버깅 용도 -> 개발, 유지 보수에 연관 -> 앱/웹 개발자 관여
- 데이터 엔지니어 관점 새로운 흐름(파이프라인 구성)
  - S3에 바로 저장 (다이렉트 저장)
    - 불필요한 I/O 아주 많이 발생 (빈번한 putObject 행위 발생)
    - 작은 파일이 많이 발생함
  - 방식
    - 해당 데이터는 실시간 스트리밍 수집 -> kinesis 활용
    - 데이터를 모아서(시간 단위, 용량 단위) 한 번에 S3에 저장 -> firehose 활용
    - Streaming Ingestion 
    - 향후 
      - kinesis -> flink(대용량, 실시간 전처리) / lambda -> kinesis -> firehose로 구성하여 silver 단계 구성 가능

# 구성도
- 기본적 스트리밍 수집
```
                      ┌→ CloudWatch Logs
                      │   운영/디버깅
Fargate Generator ────┤
                      │
                      └→ Kinesis
                           │
                           │
                           ↓
                        Firehose
                           ↓
                           S3 : bronze layer (메달리온 아킥텍처 기반)
                      데이터 파이프라인
```

# 메달리온 아키텍처
- 데이터 레이크(하우스)의 표준 데이터 품질 관리 패턴
- 구성

|단계|의미|뉘앙스|
|--|--|--|
|Bronze|가공되지 않은 기록<br>raw 데이터|무슨 일이 일어났는가?, gzip|
|Silver|전처리, 클리닝 등 데이터 정제 과정<br>분석 가능한 깔끔한 테이블|누가, 언제, 무엇을 구매했는가?, parquet|
|Gold|보고서에 바로 들어갈 숫자, 분석, 대시보드 등<br>즉시 사용(비즈니스)할 수준의 데이터 레벨|이번 시간 매출은 얼마인가?, parquet|

# 수정 및 추가 workflow 
```
[1] dev1 Terraform 인프라 생성
       │
       ├─ Kinesis Data Stream
       ├─ S3 Bucket
       ├─ Firehose IAM Role
       └─ Firehose
       │
       ▼
[2] 기존 Fargate IAM 수정
       │
       └─ Task Role + kinesis:PutRecord(s)
       │
       ▼
[3] Python 로그 생성기 수정
       │
       ├─ config.py
       ├─ output.py
       └─ main.py
       │
       ▼
[4] Docker 이미지 재빌드
       │
       ▼
[5] run-generator.bat/shell 수정
       │
       ▼
[6] 실행
       │
       ▼
Fargate → Kinesis → Firehose → S3 확인 (jsonl, gzip)
```

# 인프라 수정 및 추가
- tree /f 명령으로 구성도에서 인프라만 추출
```
# 수정은 표기 안 함
├─infra
│  │  ecr.tf            # 유지
│  │  ecs.tf            # 9. 수정
│  │  iam.tf            # 6/8. 수정 (6.firehose 관련, 8.ecs-task에서 kinesis put 처리)
│  │  locals.tf         # 3. 수정
│  │  logs.tf           # 유지
│  │  output.tf         # 10. 수정                  
│  │  provider.tf       # 1. 수정
│  │  sg.tf             # 유지
│  │  variables.tf      # 2. 수정
│  │  version.tf        # 유지  
│  │  vpc.tf            # 유지
│  │
│  │  kinesis.tf        # 4. 신규
│  │  firehose.tf       # 7. 신규
│  │  s3.tf             # 5. 신규
```

# 파이썬 검토 (kinesis로 전송 조정)
- 패키지
       ```
       Faker
       boto3 # AWS SDK 패키지
       ```
       - 로컬 PC에 boto3 설치
       ```
              pip install boto3
       ```
- config.py  
       - ecs 세팅한 환경 변수 전달
- output.py
       - 출력 방향에 kinesis 추가
- main.py
       - 생성자 매개 변수 조정

# bat, shell 수정
- 코드 수정 -> 이미지 수정 -> ecr 업데이트 -> setup.bat/sh
```
# setup.bat
docker build --no-cache --platform linux/amd64 -t "$REPO:latest" "$GENERATOR"

# setup.sh
docker build --no-cache --platform linux/arm64 -t "$REPO:latest" "$GENERATOR"       
```

# 브론즈 데이터 생성
- 명령 옵션
```
ecommerce       도메인
5               5초 실행
5               기본 5 RPS
0.05            오염 데이터 5%
1               Fargate Task 1개
ap-northeast-2  서울 리전
1               Time Scale 1배
```
- 명령
- 25건 로그 생성
- CloudWatch 로그 기록됨 (stdout 설정이 기본)
- kinesis -> firehose -> s3 기록됨 (ecs 설정에 환경 변수로 세팅되어 있음)
- s3에서 로그 발생 후 언제 확인 가능한가? -> 약간의 텀 존재함, 1분 이후 혹은 1Mib(firehose 버퍼링 조건) 초과 이후 확인 가능함
```
# 윈도우
scripts/run-generator.bat 5 5 0.05 1 ap-northeast-2 1
# 맥
sh /scripts/run-generator.sh 5 5 0.05 1 ap-northeast-2 1
```

- 실시간 로그 확인
```
aws logs tail "/ecs/de-ai-16-loggen" --follow --region "ap-northeast-2"
---
2026-08-20T05:52:08.605000+00:00 generator/log-generator/33339d6f07564fefbdc2c747f015322d {"schema_version":"1.0","record_type":"application_log","event_id":"2e5556ff-3dbd-4832-a5e1-545b653d246f","trace_id":"ceccb7d8da9c4ec287a5fd9050f05a22","run_id":"loggen-1692416937-24008","occurred_at":"2026-08-20T14:52:08.605+09:00","generated_at_utc":"2026-08-20T05:52:08.605+00:00","domain":"ecommerce","event_type":"search","service":{"name":"commerce-api","environment":"simulation","instance_id":"sim-07"},"client":{"ip":"210.207.253.196","user_agent":"Mozilla/5.0 Chrome/151.0 Android/15","device_id":"ae097f9c71064994"},"request":{"method":"GET","path":"/api/search","request_bytes":419},"response":{"status_code":200,"latency_ms":68,"response_bytes":1331},"data":{"user_id":"usr_813419","session_id":"4ebde4632c9a4d238013","product_id":"prd_14420","category":"electronics","quantity":1,"unit_price":292300,"currency":"KRW","campaign":null,"keyword":"at","result_count":122}}
```

# jsonl -> gzip 변경하여 저장 (실습)
- 동일 로그 발생 -> 최종 결과물 GZIP으로 저장
- 조치
       - 수정
       ```
       # ~/infra/firehose.tf 
       # 주석 처리
       # compression_format = "UNCOMPRESSED" # 1차는 원본 지정, 활성화되지 않음
       # 주석 해제
       compression_format = "GZIP" # GZIP으로 압축
       ```
       - 인프라 반영
       ```
       terraform -chdir=infra apply
       ```
       - 로그 발생
       ```
       scripts/run-generator.bat game 5 5 0.05 1 ap-northeast-2 1
       ```
       - S3 확인
       ```
       de-ai-16-loggen-firehose-3-2026-08-20-15-30-35-8ec009b8-ed85-484b-be3a-29ec5db83adb.gz
       ```