locals {
  # 자동으로 계산하여 AZ 영역 결정 -> a, b 선택될 것임
  availability_zones = slice(
    data.aws_availability_zones.available.names, # 사용 가능한 az 목록
    0,                                           # 시작 인덱스
    length(var.public_subnet_cidrs)              # 끝 인덱스 -> 2
  )

  # 기타 이름 설정
  cluster_name    = "${var.project_name}-cluster"
  task_family     = "${var.project_name}-task"
  repository_name = "${var.project_name}-repository"
  log_group_name  = "/ecs/${var.project_name}"

  # [브론즈 추가]
  # 데이터 스트림, 파이어호스 이름 구성
  kinesis_stream_name = "${var.project_name}-kinesis"
  firehose_name       = "${var.project_name}-firehose"
}
