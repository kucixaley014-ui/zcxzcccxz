Flutter Android bootstrap project (minimal)

Contents:
- lib/main.dart     (app code)
- pubspec.yaml
- .github/workflows/flutter.yml  (CI to build apk)
- bootstrap.sh      (run to generate android/ using Flutter CLI)

Usage locally:
  1. Install Flutter SDK: https://flutter.dev/docs/get-started/install
  2. Unzip this archive and cd into folder.
  3. Run: ./bootstrap.sh
     (this will run 'flutter create . --platforms android' to generate android/)
  4. Commit everything to a git repo and push to GitHub.

Usage in CI:
- The GitHub Actions workflow included will run 'flutter build apk' and upload artifact.
- If you want CI to create android/ automatically, ensure the runner has Flutter installed and allow bootstrap to run.
