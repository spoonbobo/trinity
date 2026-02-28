FROM ghcr.io/cirruslabs/flutter:stable

WORKDIR /app
COPY pubspec.yaml pubspec.lock* ./
RUN flutter pub get

COPY . .
ARG GATEWAY_TOKEN=replace-me-with-a-real-token
RUN flutter build web --release --dart-define=GATEWAY_TOKEN=$GATEWAY_TOKEN

CMD ["cp", "-r", "/app/build/web/.", "/output/"]
