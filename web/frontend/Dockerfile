FROM ghcr.io/cirruslabs/flutter:stable

WORKDIR /app
COPY pubspec.yaml pubspec.lock* ./
RUN flutter pub get

COPY . .
RUN flutter build web --release

CMD ["cp", "-r", "/app/build/web/.", "/output/"]
