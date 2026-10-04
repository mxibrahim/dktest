# Free-tier friendly baseline (10 alarms free). Application-level metrics
# (heap, cluster health, disk watermarks) are discussed in the README.

# Host-level failure: let EC2 recover the instance onto healthy hardware.
resource "aws_cloudwatch_metric_alarm" "system_status" {
  count = var.node_count

  alarm_name          = "${aws_instance.es[count.index].tags.Name}-system-status"
  alarm_description   = "Underlying AWS host failed; auto-recover the instance."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  dimensions          = { InstanceId = aws_instance.es[count.index].id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  alarm_actions = compact([
    "arn:aws:automate:${data.aws_region.current.region}:ec2:recover",
    var.alarm_sns_topic_arn,
  ])
}

# Sustained CPU exhaustion on a burstable instance = credits running out.
resource "aws_cloudwatch_metric_alarm" "cpu_credits" {
  count = var.node_count

  alarm_name          = "${aws_instance.es[count.index].tags.Name}-cpu-credits-low"
  alarm_description   = "CPU credit balance low; node will be throttled to baseline."
  namespace           = "AWS/EC2"
  metric_name         = "CPUCreditBalance"
  dimensions          = { InstanceId = aws_instance.es[count.index].id }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 3
  threshold           = 10
  comparison_operator = "LessThanThreshold"

  alarm_actions = compact([var.alarm_sns_topic_arn])
}

data "aws_region" "current" {}
