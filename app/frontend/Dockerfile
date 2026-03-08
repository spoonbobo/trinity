FROM ghcr.io/cirruslabs/flutter:stable

WORKDIR /app

# Copy pre-downloaded fonts from build context (fonts/ directory).
# To populate: run the font download script or copy font files into fonts/.
COPY fonts/ fonts/

COPY pubspec.yaml pubspec.lock* ./
RUN flutter pub get

COPY . .
ARG GATEWAY_WS_URL=ws://localhost/ws
ARG TERMINAL_WS_URL=ws://localhost/terminal/
ARG AUTH_SERVICE_URL=http://localhost
ARG SUPABASE_ANON_KEY=
RUN flutter build web --release \
    --dart-define=GATEWAY_WS_URL=$GATEWAY_WS_URL \
    --dart-define=TERMINAL_WS_URL=$TERMINAL_WS_URL \
    --dart-define=AUTH_SERVICE_URL=$AUTH_SERVICE_URL \
    --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY

CMD ["cp", "-r", "/app/build/web/.", "/output/"]
