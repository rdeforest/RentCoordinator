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
- **Frontend:** CoffeeScript compiled to JavaScript (no bundler)
- **Infrastructure:** AWS (EC2, ALB, CloudFormation, CloudWatch)
- **Payments:** Stripe (ACH Direct Debit)

## Status

### Known Issues

- Timer for current task doesn't change dynamically
- Cannot change 'selected' task without resuming first
- Switching between 'timer' and 'work management' could be more intuitive

For the up-to-date bug list with reproduction steps and proposed fixes,
see `docs/bugs/` and `docs/fixes/`. For commit history, use `git log`.

