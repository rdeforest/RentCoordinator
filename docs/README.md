# RentCoordinator

Tool for coordinating efforts, reimbursements, plans and rent payments with Lyndzie.

## Features

- **Work Tracking** - Timer-based and manual work entry
- **Rent Management** - Monthly rent tracking with automatic calculations
- **Payment Processing** - ACH payments via Stripe
- **Time Tracking** - Session-based timer with pause/resume
- **Reporting** - Work logs and rent history

## Documentation

- **[Disaster Recovery Guide](disaster-recovery.md)** - Infrastructure and recovery procedures
- **[CloudWatch Logs Setup](cloudwatch-logs-setup.md)** - Centralized logging configuration
- **[Deployment Guide](deployment.md)** - Deployment procedures and scripts

## Technology Stack

- **Backend:** Node.js, CoffeeScript, Express
- **Database:** SQLite with S3 backups
- **Frontend:** Vanilla JavaScript, CoffeeScript
- **Infrastructure:** AWS (EC2, ALB, CloudFormation, CloudWatch)
- **Payments:** Stripe (ACH Direct Debit)

## Recent Updates

### 2025-12-29
- Fixed payment error handling for ACH payments
- Added comprehensive Stripe API status handling
- Fixed SQL parameter binding bug in manual work entry
- Deployed CloudWatch Logs for centralized logging
- Enhanced error logging on client and server

### 2025-11-05
- Implemented disaster recovery with automated backups
- Added backup/restore system with S3 versioning

## Status

### Known Issues

- Timer for current task doesn't change dynamically
- Cannot change 'selected' task without resuming first
- Switching between 'timer' and 'work management' could be more intuitive

