# frozen_string_literal: true

# Normalizes the CRM OAuth authorization URL before it reaches the router.
#
# The backed.crm client can construct the authorization URL from a multi-line
# template literal, producing encoded newlines (%0A / %0D) in both the path
# and the query string, and HTML-encoded ampersands (&amp;) as parameter
# separators.  For example the broken URL looks like:
#
#   /api/integrations/crm/authorize%0A%20%20
#     ?client_id=backed-crm%0A%20%20
#     &amp;redirect_uri=https://…%0A%20%20
#     &amp;state=…
#
# This middleware detects requests to the CRM authorize path (including ones
# where the path itself contains a newline) and strips those artefacts so that:
#
#   1. The Rails router can match the route.
#   2. The parameters reach the controller without embedded whitespace.
#   3. `&amp;` query separators are converted to real `&`.
class NormalizeCrmUrlMiddleware
  # Matches a percent-encoded newline (LF or CR) followed by zero or more
  # percent-encoded spaces – the exact pattern emitted by a multi-line JS
  # template literal after encodeURIComponent / URL construction.
  ENCODED_NEWLINE_RE = /(%0[AD])(%20)*/i

  def initialize(app)
    @app = app
  end

  def call(env)
    path = env['PATH_INFO'].to_s

    # Detect the CRM authorize path even when it contains embedded newlines
    # (PATH_INFO is URL-decoded by Rack, so %0A arrives as "\n").
    if path.include?('/crm/authorize')
      env['PATH_INFO']    = path.gsub(/[\r\n]+[ \t]*/, '')
      env['QUERY_STRING'] = normalize_query(env['QUERY_STRING'].to_s)
    end

    @app.call(env)
  end

  private

  def normalize_query(query)
    # 1. Remove encoded newlines (and any trailing encoded spaces) from param
    #    names and values.
    # 2. Convert HTML-encoded ampersand to the real separator so that Rails can
    #    parse the query string correctly.
    query.gsub(ENCODED_NEWLINE_RE, '').gsub('&amp;', '&')
  end
end
