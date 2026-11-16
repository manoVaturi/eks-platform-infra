# Cost alarms by e-mail. AWS Budgets are free (the first two per account) and they are the safety net for a forgotten down.sh:
# a normal working day costs about $3 to $4, a day with everything left on about $9.

resource "aws_budgets_budget" "daily" {
  name         = "weatherapp-daily"
  budget_type  = "COST"
  time_unit    = "DAILY"
  limit_amount = var.daily_budget_usd
  limit_unit   = "USD"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }
}

resource "aws_budgets_budget" "monthly" {
  name         = "weatherapp-monthly"
  budget_type  = "COST"
  time_unit    = "MONTHLY"
  limit_amount = var.monthly_budget_usd
  limit_unit   = "USD"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_email]
  }
}
