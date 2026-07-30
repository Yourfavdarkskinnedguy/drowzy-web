// =============================================================================
//  supabase/functions/send-waitlist-email/index.ts — Drowzy
// =============================================================================

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';

// =============================================================================
//  TYPES
// =============================================================================

interface WaitlistPayload {
  email: string;
  queue_position: number;
  referral_link: string;
  referral_code: string;
}

// =============================================================================
//  EMAIL HELPER (with timeout & error handling)
// =============================================================================

async function sendWaitlistEmail(payload: WaitlistPayload) {
  const apiKey = Deno.env.get('BREVO_API_KEY');
  if (!apiKey) {
    console.error('BREVO_API_KEY not set — cannot send email');
    return;
  }

  const emailData = {
    sender: { name: 'Drowzy', email: 'support@drowzy.app' },
    to: [{ email: payload.email }],
    subject: `You're #${payload.queue_position} on the Drowzy waitlist!`,
    htmlContent: `<!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>You're on the Drowzy waitlist!</title>
      </head>
      <body style="margin:0; padding:0; background-color:#060B14; font-family:Arial, Helvetica, sans-serif;">
        <table width="100%" cellpadding="0" cellspacing="0" style="background: radial-gradient(circle at 30% 10%, #0F2240 0%, #060B14 70%); padding:40px 0;">
          <tr>
            <td align="center">
              <table width="560" cellpadding="0" cellspacing="0" style="background-color:#0C1628; border-radius:20px; border:1px solid #1A2845; box-shadow: 0 8px 32px rgba(0,0,0,0.5), 0 2px 8px rgba(0,229,204,0.08); max-width:560px;">
                <tr>
                  <td style="padding:36px 32px 20px 32px; text-align:center;">
                    <h1 style="color:#00E5CC; margin:0; font-size:28px; font-weight:800; letter-spacing:-0.5px;">Drowzy</h1>
                    <p style="color:#7A8499; font-size:14px; margin:4px 0 0 0; letter-spacing:0.5px;">Stay Alert. Drive Safe.</p>
                  </td>
                </tr>
                <tr>
                  <td style="padding:0 32px;">
                    <hr style="border:none; border-top:1px solid #1A2845; margin:0;">
                  </td>
                </tr>
                <tr>
                  <td style="padding:28px 32px 16px 32px; text-align:center;">
                    <h2 style="color:#FFFFFF; margin:0; font-size:22px; font-weight:700; letter-spacing:-0.3px;">
                      You're on the list! 🎉
                    </h2>
                    <p style="color:#94A3B8; font-size:15px; line-height:1.6; margin:14px 0 0 0;">
                      Drowzy is almost ready. You're spot <strong style="color:#00E5CC;">#${payload.queue_position}</strong> — we'll email you the moment we launch.
                    </p>
                  </td>
                </tr>
                <tr>
                  <td style="padding:12px 32px 28px 32px;">
                    <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#08101E; border-radius:12px; padding:20px 24px;">
                      <tr>
                        <td style="padding:0 0 10px 0;">
                          <p style="color:#FFFFFF; font-size:14px; font-weight:600; margin:0;">Move up the queue 🚀</p>
                        </td>
                      </tr>
                      <tr>
                        <td style="padding:0 0 14px 0;">
                          <p style="color:#94A3B8; font-size:13px; line-height:1.5; margin:0;">
                            Share your personal link. When friends join, you skip ahead.
                          </p>
                        </td>
                      </tr>
                      <tr>
                        <td style="background-color:#0C1628; border-radius:8px; padding:10px 14px;">
                          <a href="${payload.referral_link}" style="color:#00E5CC; text-decoration:none; font-size:13px; word-break:break-all;">${payload.referral_link}</a>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
                <tr>
                  <td style="padding:0 32px;">
                    <hr style="border:none; border-top:1px solid #1A2845; margin:0;">
                  </td>
                </tr>
                <tr>
                  <td style="padding:24px 32px 12px 32px;">
                    <p style="color:#94A3B8; font-size:12px; line-height:1.7; margin:0;">
                      You'll receive a single email when Drowzy launches. No spam, no nonsense.
                    </p>
                    <p style="color:#475569; font-size:11px; line-height:1.6; margin:12px 0 0 0;">
                      Need help? Reply to this email or contact us at
                      <a href="mailto:support@drowzy.app" style="color:#00E5CC; text-decoration:none;">support@drowzy.app</a>.
                    </p>
                  </td>
                </tr>
                <tr>
                  <td style="padding:16px 32px 28px 32px; text-align:center;">
                    <p style="color:#475569; font-size:10px; margin:0;">
                      &copy; ${new Date().getFullYear()} Drowzy. All rights reserved.
                    </p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
      </body>
      </html>`,
  };

  // ── Send with a 5‑second timeout ──
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 5_000);

  try {
    const res = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: {
        'api-key': apiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(emailData),
      signal: controller.signal,
    });

    if (!res.ok) {
      const errText = await res.text();
      console.error('Brevo API error:', res.status, errText);
    } else {
      console.log('Email sent successfully to', payload.email);
    }
  } catch (error) {
    console.error('Brevo request failed:', error.message);
  } finally {
    clearTimeout(timeout);
  }
}

// =============================================================================
//  HANDLER (CORS‑fixed)
// =============================================================================

serve(async (req: Request) => {
  // ── CORS headers added to EVERY response ──
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
  };

  // Handle preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  // Only POST allowed
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed.' }), {
      status: 405,
      headers: { 'Content-Type': 'application/json', ...corsHeaders },
    });
  }

  try {
    const payload: WaitlistPayload = await req.json();

    if (!payload.email || !payload.referral_link) {
      return new Response(JSON.stringify({ error: 'Missing required fields.' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json', ...corsHeaders },
      });
    }

    // Fire and forget — email sending doesn't block the response
    sendWaitlistEmail(payload).catch(console.error);

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json', ...corsHeaders },
    });
  } catch (err) {
    console.error('Handler error:', err);
    return new Response(JSON.stringify({ error: 'Internal server error.' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json', ...corsHeaders },
    });
  }
});