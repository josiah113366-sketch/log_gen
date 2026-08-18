# fargate를 통해서 task 작동 -> stdout/stderr 등 발생 -> CloudWatch에 저장
resource "aws_cloudwatch_log_group" "generator" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days # 보관 기간 이후 로그 자동 삭제
}