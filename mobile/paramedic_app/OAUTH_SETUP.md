# Google / Apple Sign-In setup

## Google
- Create an OAuth client for the Flutter platforms you ship.
- Set GOOGLE_WEB_CLIENT_ID on the FastAPI server to the server/web client ID used for ID-token audience validation.
- Configure Android SHA-1/SHA-256 and iOS URL scheme according to the google_sign_in package documentation.
- The app sends the Google ID token to POST /auth/oauth/google; the backend verifies it before issuing the RescuPath JWT.

## Apple
- Configure Sign in with Apple for the iOS bundle identifier and a Service ID when using web/Android flows.
- Set APPLE_SERVICE_ID on FastAPI.
- The backend downloads Apple's JWKS and validates the identity token issuer, audience and signature.
- Configure the platform capability/redirect settings in Xcode and Apple Developer.

Do not hard-code client secrets or private keys into the Flutter app.
