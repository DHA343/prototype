# 音声

- `SoundCue` に音源、バス、音量、ピッチ、集約方法、同時発音数を設定する。
- `WorldSoundOutput.request(SoundRequest.new(cue, world_position, source))` で再生を要求する。
- 同一フレーム・時間窓の集約、同一フレームの重複抑制、Cue単位・全体の発音数制限を引き継ぐ。
- 集約した要求は後で再生される。`request()` の成功は、実際に音が鳴ったことを保証しない。
- `default_bus_layout.tres` のMaster / SFX設定と既存の衝突音を維持する。
