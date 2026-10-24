/// Invalidates async results as soon as the user's input changes.
class LatestRequest {
  int _version = 0;
  int get version => _version;
  int next() => ++_version;
  bool accepts(int version) => version == _version;
}
