#!/usr/bin/env bash
# backup.sh — BROKEN BASELINE (God-Script)
#
# This script handles database backups, S3 uploads, and Slack notifications.
# It was written by three different people over two years with no coordination.
#
# Problems:
#   - No functions (everything is inline, duplicated)
#   - No error handling (set -e was removed "because it broke things")
#   - curl commands copy-pasted 9 times with slight variations
#   - Hardcoded credentials scattered throughout
#   - No cleanup on failure
#   - 300+ lines of spaghetti
#
# Goal: Refactor following the Stepdown Rule — functions < 20 lines,
#       proper trap/error handling, no duplication, shellcheck clean.

# ──────────────────────────────────────────────────────────────────────────
# SECTION 1: BACKUP DATABASE — production
# ──────────────────────────────────────────────────────────────────────────

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/backups"
mkdir -p $BACKUP_DIR

echo "Starting backup for production database..."
PGPASSWORD="prod_secret_123" pg_dump -h db-prod.internal -U admin -d production -F c -f $BACKUP_DIR/production_$DATE.dump
if [ $? -ne 0 ]; then
  echo "pg_dump failed for production"
fi

echo "Compressing production backup..."
gzip $BACKUP_DIR/production_$DATE.dump
if [ $? -ne 0 ]; then
  echo "gzip failed"
fi

echo "Uploading production backup to S3..."
AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE" AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" aws s3 cp $BACKUP_DIR/production_$DATE.dump.gz s3://mycompany-backups/production/$DATE/ --region us-east-1
if [ $? -ne 0 ]; then
  echo "S3 upload failed for production"
fi

echo "Cleaning up production backup..."
rm -f $BACKUP_DIR/production_$DATE.dump.gz

echo "Sending Slack notification for production..."
curl -s -X POST YOUR_SLACK_WEBHOOK_URL \
  -H 'Content-type: application/json' \
  -d "{\"text\": \"✅ Production DB backup completed: production_${DATE}.dump.gz\"}"

# ──────────────────────────────────────────────────────────────────────────
# SECTION 2: BACKUP DATABASE — staging
# ──────────────────────────────────────────────────────────────────────────

echo "Starting backup for staging database..."
PGPASSWORD="staging_secret_456" pg_dump -h db-staging.internal -U admin -d staging -F c -f $BACKUP_DIR/staging_$DATE.dump
if [ $? -ne 0 ]; then
  echo "pg_dump failed for staging"
fi

echo "Compressing staging backup..."
gzip $BACKUP_DIR/staging_$DATE.dump
if [ $? -ne 0 ]; then
  echo "gzip failed for staging"
fi

echo "Uploading staging backup to S3..."
AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE" AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" aws s3 cp $BACKUP_DIR/staging_$DATE.dump.gz s3://mycompany-backups/staging/$DATE/ --region us-east-1
if [ $? -ne 0 ]; then
  echo "S3 upload failed for staging"
fi

echo "Cleaning up staging backup..."
rm -f $BACKUP_DIR/staging_$DATE.dump.gz

echo "Sending Slack notification for staging..."
curl -s -X POST YOUR_SLACK_WEBHOOK_URL \
  -H 'Content-type: application/json' \
  -d "{\"text\": \"✅ Staging DB backup completed: staging_${DATE}.dump.gz\"}"

# ──────────────────────────────────────────────────────────────────────────
# SECTION 3: BACKUP DATABASE — analytics
# ──────────────────────────────────────────────────────────────────────────

echo "Starting backup for analytics database..."
PGPASSWORD="analytics_secret_789" pg_dump -h db-analytics.internal -U readonly -d analytics -F c -f $BACKUP_DIR/analytics_$DATE.dump
if [ $? -ne 0 ]; then
  echo "pg_dump failed for analytics"
fi

echo "Compressing analytics backup..."
gzip $BACKUP_DIR/analytics_$DATE.dump
if [ $? -ne 0 ]; then
  echo "gzip failed for analytics"
fi

echo "Uploading analytics backup to S3..."
AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE" AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" aws s3 cp $BACKUP_DIR/analytics_$DATE.dump.gz s3://mycompany-backups/analytics/$DATE/ --region us-east-1
if [ $? -ne 0 ]; then
  echo "S3 upload failed for analytics"
fi

echo "Cleaning up analytics backup..."
rm -f $BACKUP_DIR/analytics_$DATE.dump.gz

curl -s -X POST YOUR_SLACK_WEBHOOK_URL \
  -H 'Content-type: application/json' \
  -d "{\"text\": \"✅ Analytics DB backup completed: analytics_${DATE}.dump.gz\"}"

# ──────────────────────────────────────────────────────────────────────────
# SECTION 4: UPLOAD LOGS TO S3
# ──────────────────────────────────────────────────────────────────────────

echo "Compressing application logs..."
LOG_DATE=$(date +%Y%m%d)
tar -czf /tmp/app_logs_${LOG_DATE}.tar.gz /var/log/app/*.log
if [ $? -ne 0 ]; then
  echo "tar failed for app logs"
fi

echo "Uploading app logs to S3..."
AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE" AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" aws s3 cp /tmp/app_logs_${LOG_DATE}.tar.gz s3://mycompany-backups/logs/app/$LOG_DATE/ --region us-east-1
if [ $? -ne 0 ]; then
  echo "S3 upload failed for app logs"
fi

rm -f /tmp/app_logs_${LOG_DATE}.tar.gz

echo "Compressing nginx logs..."
tar -czf /tmp/nginx_logs_${LOG_DATE}.tar.gz /var/log/nginx/*.log
if [ $? -ne 0 ]; then
  echo "tar failed for nginx logs"
fi

echo "Uploading nginx logs to S3..."
AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE" AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" aws s3 cp /tmp/nginx_logs_${LOG_DATE}.tar.gz s3://mycompany-backups/logs/nginx/$LOG_DATE/ --region us-east-1
if [ $? -ne 0 ]; then
  echo "S3 upload failed for nginx logs"
fi

rm -f /tmp/nginx_logs_${LOG_DATE}.tar.gz

echo "Compressing postgres logs..."
tar -czf /tmp/pg_logs_${LOG_DATE}.tar.gz /var/log/postgresql/*.log
if [ $? -ne 0 ]; then
  echo "tar failed for postgres logs"
fi

echo "Uploading postgres logs to S3..."
AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE" AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" aws s3 cp /tmp/pg_logs_${LOG_DATE}.tar.gz s3://mycompany-backups/logs/postgres/$LOG_DATE/ --region us-east-1
if [ $? -ne 0 ]; then
  echo "S3 upload failed for postgres logs"
fi

rm -f /tmp/pg_logs_${LOG_DATE}.tar.gz

curl -s -X POST YOUR_SLACK_WEBHOOK_URL \
  -H 'Content-type: application/json' \
  -d "{\"text\": \"✅ Log archives uploaded: app, nginx, postgres for $LOG_DATE\"}"

# ──────────────────────────────────────────────────────────────────────────
# SECTION 5: ROTATE OLD BACKUPS (delete files older than 30 days)
# ──────────────────────────────────────────────────────────────────────────

echo "Rotating old backups on S3..."
CUTOFF=$(date -d "30 days ago" +%Y-%m-%d 2>/dev/null || date -v-30d +%Y-%m-%d)

AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE" AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" aws s3 ls s3://mycompany-backups/production/ --region us-east-1 | while read -r line; do
  file_date=$(echo $line | awk '{print $1}')
  file_name=$(echo $line | awk '{print $4}')
  if [[ "$file_date" < "$CUTOFF" ]]; then
    AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE" AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" aws s3 rm s3://mycompany-backups/production/$file_name --region us-east-1
    echo "Deleted old production backup: $file_name"
  fi
done

AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE" AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" aws s3 ls s3://mycompany-backups/staging/ --region us-east-1 | while read -r line; do
  file_date=$(echo $line | awk '{print $1}')
  file_name=$(echo $line | awk '{print $4}')
  if [[ "$file_date" < "$CUTOFF" ]]; then
    AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE" AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" aws s3 rm s3://mycompany-backups/staging/$file_name --region us-east-1
    echo "Deleted old staging backup: $file_name"
  fi
done

AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE" AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" aws s3 ls s3://mycompany-backups/analytics/ --region us-east-1 | while read -r line; do
  file_date=$(echo $line | awk '{print $1}')
  file_name=$(echo $line | awk '{print $4}')
  if [[ "$file_date" < "$CUTOFF" ]]; then
    AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE" AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" aws s3 rm s3://mycompany-backups/analytics/$file_name --region us-east-1
    echo "Deleted old analytics backup: $file_name"
  fi
done

curl -s -X POST YOUR_SLACK_WEBHOOK_URL \
  -H 'Content-type: application/json' \
  -d "{\"text\": \"🗑️ Rotation complete: deleted backups older than $CUTOFF\"}"

# ──────────────────────────────────────────────────────────────────────────
# SECTION 6: HEALTH CHECK PINGS
# ──────────────────────────────────────────────────────────────────────────

echo "Checking production health..."
PROD_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://app-prod.internal/health)
if [ "$PROD_STATUS" != "200" ]; then
  curl -s -X POST YOUR_SLACK_WEBHOOK_URL \
    -H 'Content-type: application/json' \
    -d "{\"text\": \"🚨 ALERT: Production health check failed! Status: $PROD_STATUS\"}"
  echo "Production health check failed: $PROD_STATUS"
else
  echo "Production is healthy: $PROD_STATUS"
fi

echo "Checking staging health..."
STAGING_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://app-staging.internal/health)
if [ "$STAGING_STATUS" != "200" ]; then
  curl -s -X POST YOUR_SLACK_WEBHOOK_URL \
    -H 'Content-type: application/json' \
    -d "{\"text\": \"⚠️ WARNING: Staging health check failed! Status: $STAGING_STATUS\"}"
  echo "Staging health check failed: $STAGING_STATUS"
else
  echo "Staging is healthy: $STAGING_STATUS"
fi

echo "Checking analytics health..."
ANALYTICS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://app-analytics.internal/health)
if [ "$ANALYTICS_STATUS" != "200" ]; then
  curl -s -X POST YOUR_SLACK_WEBHOOK_URL \
    -H 'Content-type: application/json' \
    -d "{\"text\": \"⚠️ WARNING: Analytics health check failed! Status: $ANALYTICS_STATUS\"}"
  echo "Analytics health check failed: $ANALYTICS_STATUS"
else
  echo "Analytics is healthy: $ANALYTICS_STATUS"
fi

echo "All done."
