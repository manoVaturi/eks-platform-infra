resource "aws_wafv2_web_acl" "main" {
  name        = "weatherapp"
  description = "WAF for weatherapp"
  scope       = "REGIONAL"

  # Requests that match no rule are allowed. The rules list what to catch, not what to let in.
  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "weatherapp-waf"
    sampled_requests_enabled   = true
  }

  # Known bad source IPs (botnets, scanners)
  rule {
    name     = "ip-reputation"
    priority = 10

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "ip-reputation"
      sampled_requests_enabled   = true
    }

    override_action {
      none {}
    }
  }

  # Known exploit patterns (Log4Shell-style payloads, probes)
  rule {
    name     = "known-bad-inputs"
    priority = 20

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "known-bad-inputs"
      sampled_requests_enabled   = true
    }

    override_action {
      none {}
    }
  }

  # More than 300 requests in 5 minutes from one IP
  rule {
    name     = "rate-limit"
    priority = 40
    statement {
      rate_based_statement {
        limit              = 300
        aggregate_key_type = "IP"
      }

    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit"
      sampled_requests_enabled   = true
    }

    action {
      block {}
    }

  }
}
