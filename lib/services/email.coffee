config = require '../config.coffee'


generateCode = ->
  Math.floor(100000 + Math.random() * 900000).toString()


sendVerificationCode = (email, code) ->
  if config.NODE_ENV is 'development'
    console.log """
      ════════════════════════════════════════
      Verification Code for #{email}

      Code: #{code}

      (In production, this would be sent via email)
      ════════════════════════════════════════
    """
    return Promise.resolve success: true

  unless config.SMTP_HOST
    throw new Error 'SMTP not configured for production'

  nodemailer = require 'nodemailer'

  transporter = nodemailer.createTransport
    host:   config.SMTP_HOST
    port:   config.SMTP_PORT
    secure: config.SMTP_PORT is 465
    auth:
      user: config.SMTP_USER
      pass: config.SMTP_PASS

  mailOptions =
    from:    config.EMAIL_FROM
    to:      email
    subject: 'RentCoordinator Verification Code'
    text: """
      Your verification code is: #{code}

      This code will expire in 10 minutes.

      If you didn't request this code, please ignore this email.
    """
    html: """
      <h2>RentCoordinator Verification</h2>
      <p>Your verification code is:</p>
      <h1 style="font-size: 32px; letter-spacing: 8px; font-family: monospace;">#{code}</h1>
      <p>This code will expire in 10 minutes.</p>
      <p style="color: #666; font-size: 12px;">If you didn't request this code, please ignore this email.</p>
    """

  await transporter.sendMail mailOptions
  return success: true

module.exports = { generateCode, sendVerificationCode }
