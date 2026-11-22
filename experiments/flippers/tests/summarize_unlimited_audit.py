"""Separate distance-gate effects, censored outcomes and usable CPU measurements."""

import collections
import hashlib
import json
import math
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
E = ROOT / "evidence"
MODES = ("baseline", "safe12", "unlimited")
LABELS = ("現行解除", "安全分離12 px", "安全分離・距離制限なし")


def read(name):
    return json.loads((E / name).read_text(encoding="utf-8-sig"))


def stats(values):
    values = sorted(values)
    return {"samples": len(values), "mean_us": statistics.mean(values), "median_us": statistics.median(values),
            "p95_us": values[math.ceil(len(values)*.95)-1], "p99_us": values[math.ceil(len(values)*.99)-1],
            "max_us": max(values)}


def main():
    audit, grid, bench, live, probe, old = (read(name) for name in (
        "unlimited_audit.json", "unlimited_grid.json", "unlimited_step_benchmark.json",
        "unlimited_runtime.json", "unlimited_benchmark.json", "release_audit.json"))
    assert audit["failures"] == grid["failures"] == bench["failures"] == 0
    assert len(grid["cases"]) == 1728 and audit["regression"] == {"cases": 4644, "trials": 3}
    assert live["single_step"] and len(live["cases"]) == 12
    for path, digest in audit["production_sha256"].items():
        assert hashlib.sha256((ROOT.parents[1] / path).read_bytes()).hexdigest() == digest
        assert bench["production_sha256"][path] == digest
    s = {"audit_checks": audit["checks"], "step_cpu_checks": bench["checks"], "failures": 0,
         "near": {}, "grid": {}, "cpu_common": {}, "cpu_all": {}, "known": {},
         "long_trajectory_probe": {"accepted_for_performance": False, "failures": probe["failures"],
            "different_trajectories": len(probe["validation_differences"]),
            "max_position_error_px": max(row["position_error_px"] for row in probe["validation_differences"]),
            "max_velocity_error_px_s": max(row["velocity_error_px_s"] for row in probe["validation_differences"])},
         "production_sha256": audit["production_sha256"]}
    for mode in MODES:
        rows = audit["integration"][mode]["near_enemy"]
        assert len(rows) == 84 and len(audit["integration"][mode]["population"]) == 2
        events = [event for row in rows for event in row.get("release_events", [])]
        corrections = [event for event in events if event["release_correction_px"] > 0]
        for event in corrections:
            assert event["release"]["flipper_clear_after"] and not event["release"]["world_after"]
            assert event["release"]["candidates"][-1]["rejected"] == ""
            assert event["release"]["released"] and not event["release"]["deferred"]
            if mode == "safe12":
                assert event["release_correction_px"] <= 12.00001
            if mode == "unlimited":
                assert event["release"]["limit_px"] is None
        failed = [row for row in rows if row["unresolved"]]
        reasons = collections.Counter()
        for row in failed:
            event = row["release_events"][-1]
            assert not event["events"] and event["guard_active"]
            assert event["position"] == event["release"]["before"]
            reasons.update(candidate["rejected"] for candidate in event["release"]["candidates"])
        s["near"][mode] = {"completed": sum(row["completed"] for row in rows), "unresolved": len(failed),
            "capped_inputs": sum(row["exhausted_updates"] > 0 for row in rows),
            "discarded_ms": sum(row["discarded_ms"] for row in rows),
            "max_correction_px": max(row["max_correction_px"] for row in rows),
            "release_corrections": len(corrections), "failed_reasons": dict(reasons),
            "introduced_events": sum(row["observed"]["E_introduced"] for row in rows),
            "reset_inputs": sum(any(tick["below_reset"] for tick in row["trajectory"]) for row in rows),
            "opening_inputs": sum(any(tick["opening_exit"] for tick in row["trajectory"]) for row in rows),
            "immediate_reset": sum(tick["release_below_to_reset"] for row in rows for tick in row["trajectory"]),
            "immediate_opening": sum(tick["release_opening_exit"] for row in rows for tick in row["trajectory"]),
            "enabled_residual_count": sum(tick["flipper_depth_px"] > 0 for row in rows
                                           for tick in row["trajectory"] if not tick["guard_active"]),
            "enabled_residual_max_px": max((tick["flipper_depth_px"] for row in rows
                                           for tick in row["trajectory"] if not tick["guard_active"]), default=0),
            "population": audit["integration"][mode]["population"], "failed_cases": failed,
            "caps": [row for row in rows if row["exhausted_updates"]]}
        entries = [row["methods"][mode] for row in grid["cases"]]
        s["grid"][mode] = {"unresolved": sum(row["unresolved"] for row in entries),
                           "released": sum(row["guard_released"] for row in entries),
                           "max_correction_px": max(row["max_correction_px"] for row in entries)}
        if mode != "unlimited":
            for current, previous in zip(rows, old["integration"][mode]["near_enemy"], strict=True):
                for key in ("completed", "unresolved", "exhausted_updates", "shots"):
                    assert current[key] == previous[key]
                assert abs(current["max_correction_px"] - previous["max_correction_px"]) < .001
    common = set(bench["common_indices"])
    assert len(common) == 1152 and len(bench["rounds"]) == 8
    for mode in MODES:
        values = [row["us"] for round_ in bench["rounds"] if not round_["warmup"]
                  for row in round_["methods"][mode] if row["index"] in common]
        s["cpu_common"][mode] = stats(values)
        if mode != "safe12":
            values = [row["us"] for round_ in bench["rounds"] if not round_["warmup"]
                      for row in round_["methods"][mode]]
            s["cpu_all"][mode] = stats(values)
    for row in live["cases"]:
        mode = MODES[int(row["mode"])]
        fixture = ((.5, 36, 0), (.7, 36, 0), (.9, 3, 0), (.15, 3, 0))[int(row["preset"])]
        expected = next(item for item in audit["integration"][mode]["near_enemy"]
                        if (item["ratio"], item["gap"], item["offset"]) == fixture)
        assert math.dist(row["position"], expected["position"]) < .001
        assert math.dist(row["velocity"], expected["trajectory"][-1]["velocity"]) < .01
        assert row["unresolved"] == expected["unresolved"] and row["caps"] == expected["exhausted_updates"]
        assert abs(row["max_correction_px"] - expected["max_correction_px"]) < .001
    for row in live["controls"]:
        assert row["distance_limited"] == (row["mode"] != 2)
    for fixture in ((.5, 36, 0), (.7, 36, 0), (.9, 3, 0), (.15, 3, 0)):
        s["known"][str(fixture)] = {mode: next(row for row in audit["integration"][mode]["near_enemy"]
            if (row["ratio"], row["gap"], row["offset"]) == fixture) for mode in MODES}
    unlimited = audit["integration"]["unlimited"]["near_enemy"]
    baseline = audit["integration"]["baseline"]["near_enemy"]
    completed = [i for i, row in enumerate(unlimited) if row["completed"]]
    s["matched_completed_outcomes"] = {"inputs": len(completed),
        "baseline_reset": sum(any(tick["below_reset"] for tick in baseline[i]["trajectory"]) for i in completed),
        "unlimited_reset": sum(any(tick["below_reset"] for tick in unlimited[i]["trajectory"]) for i in completed)}
    s["largest_correction"] = max((event for row in unlimited for event in row.get("release_events", [])),
                                   key=lambda event: event["release_correction_px"])
    s["runtime_matches_cli"] = True
    (E / "unlimited_audit_summary.json").write_text(json.dumps(s, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    report(s)
    print("Unlimited accuracy, controls, finite-candidate safety, single-step CPU and runtime validation passed.")
    print("Long-trajectory CPU probe excluded:", s["long_trajectory_probe"])
    print("Near outcomes:", {mode: {key: s["near"][mode][key] for key in
          ("completed", "unresolved", "capped_inputs", "max_correction_px", "reset_inputs")} for mode in MODES})


def report(s):
    lines = ["# ③解除時の安全分離：距離上限だけを外した比較（2026-11-23）", "",
             "## 結果と採否", "",
             "距離上限を外すと、近接Enemyの未解消は19→3配置へ減った。しかし最大249.01489 pxの水平補正、"
             "後続の通常接触による新規干渉5イベント、共有8接触の上限到達1配置、落下経路の増加が残る。"
             "全84配置を完走する要件を満たさず、現状のまま本番採用しない。", "",
             "| 構成 | 完走 / 84 | 未解消終了 | 接触上限へ到達 | 最大補正 px |",
             "| --- | ---: | ---: | ---: | ---: |"]
    for mode, label in zip(MODES, LABELS):
        row = s["near"][mode]
        lines.append(f'| {label} | {row["completed"]} | {row["unresolved"]} | {row["capped_inputs"]} | {row["max_correction_px"]:.5f} |')
    lines += ["", "現行解除も実験用の3条件＋新接触法線分離を共通基準としている。従来の打球条件へ戻した比較ではない。"
              "未解消ではその試行を停止し、延期や大きい上向き補正へのフォールバックは行わない。"
              "完走は予定60更新まで試行したことを指し、上限到達による残り時間破棄とは別集計。", "",
              "## 変更したもの・固定したもの", "",
              "`release.gd`に距離判定の有効フラグを追加し、制限なし構成だけで無効にした。"
              "有限の接触法線・上下左右候補、短い順の検査、0.151 pxの分離余裕、0.03 pxの安全余裕、"
              "重なりを深める方向の棄却、補正先・補正経路の安全条件は維持した。"
              "診断用に補正直後の実座標と、候補先を塞ぐ物体名も記録した。", "",
              "検出B・打球3条件・新接触の法線分離・③の左右共通管理・上向き探索16回・共有8接触は固定。"
              "本番main、PinballMotion、PinballFlippers、TableFlipper、Enemyは変更していない。"
              "ここでの最短は生成した候補内の最短であり、あらゆる方向からの最短安全位置ではない。", "",
              "## 試験", "",
              "- 前回の解除時1,728入力（開始重なり288×停止/回転×30/60/120 Hz）を3構成で再実行。",
              "- 近接Enemy84配置を各60更新、1球/20球を各360更新。補正後も同じ応答で移動し、毎更新の座標・速度・接触・③・深さ・開口通過を記録。",
              "- 既知の停止板2配置、回転中右側面、249 px補正の4配置を描画付きで再現。",
              "- 通常接触4,644入力×3構成は前回の組み合わせ案の位置・速度と一致。前回の12 px制限付きと現行解除の1,728入力も一致。", "",
              "停止/回転の判定と解除前照会は同じ時刻の姿勢を使う。周囲のEnemyは既存の更新順で進めた物理世界を使い、"
              "Enemyの過去姿勢復元は行わない。前回の独立安全検査（薄壁横断、開始重なりからの退出等）も通過した。", "",
              "## 既知3配置", "",
              "| 配置 ratio / gap / offset | 制限なしの結果 |", "| --- | --- |",
              "| 0.5 / 36 / 0、停止上面28.49 px | 未解消終了。上側2候補はEnemy、左側は下側壁Lower、右/下は方向条件で棄却 |",
              "| 0.7 / 36 / 0、停止上面40.59 px | 同様に未解消終了 |",
              "| 0.9 / 3 / 0、回転右側面24.49 px | 右へ24.64172 px補正、60更新完走、上限到達0。従来の上向き60.60965 pxより補正距離は小さい |", "",
              "停止板2配置の『上限到達0』は、球を動かす前に未解消で終了したためであり、反復を解決した結果ではない。"
              "残る3件目はratio=0.7/gap=36/offset=36で、同じく上側がEnemy、左側がLower、右/下が方向条件で棄却された。", "",
              "3配置での棄却理由は候補15個中、補正先の重なり9、重なりを深める方向6。"
              "各候補は最初の棄却理由を記録しており、後続条件もすべて評価したという意味ではない。"
              "『現在の候補と安全条件では見つからない』という結果で、安全な場所自体が存在しない証明ではない。", "",
              "## 大きな補正と、その後の反復", "",
              "最大補正はratio=0.15/gap=3/offset=0の更新1。上面の幾何的深さ12.16233 pxに対し、"
              "法線方向12.31333 pxと真上12.61523 pxの候補はEnemyで塞がれ、左/下候補は方向条件で棄却された。"
              "残った右方向249.01489 pxが採用され、球中心Xは693.13611→942.15100へ移動した。"
              "補正経路と補正先は安全条件を通過したが、位置の飛び自体がゲームとして自然かは別の判断である。", "",
              "![249 px補正前・更新1](unlimited_jump_before.png)", "",
              "![249 px補正後・更新2](unlimited_jump_after.png)", "",
              "新しい上限到達はratio=0.99/gap=12/offset=36、更新1。解除前の安全分離後、"
              "残り時間内に左板と再接触し、従来の上向き補正とEnemy接触が繰り返されて8回へ到達。"
              "破棄時間は9.624652 ms。球の更新開始時には重なっていたという履歴を維持したため、"
              "補正後に区間開始が非接触でも、その更新内の独自再接触は上向き分離を使っていた。"
              "今回、この分類や反復上限を同時に変更していない。", "",
              "## 干渉と落下の評価", "",
              "距離制限なしの解除前分離23イベントは、補正直後に0.03 px余裕付きの左右板判定で接触0、周囲の接触0。"
              "しかし後続の通常処理では新規干渉5イベントが発生した。現行解除は24、12 px方式は0だが、"
              "後者は19配置で早期終了しているため、0をそのまま優位とは評価しない。", "",
              "衝突再有効時の更新終了に残った板との重なりは、現行解除3イベント・最大1.13772 px、"
              "距離制限なし1イベント・最大0.00634 px。③で許可された通過や未解消終了時の内部状態はこの件数に含めない。", "",
              "近接の全84配置でmainのリセット判定Yへ到達した入力は現行7、制限なし14。"
              "両方が完走した同じ81入力だけでも現行6→制限なし14となり、8入力で新たに到達した。"
              "解除前の補正そのもので直ちにリセット判定Yや開口の退出条件へ飛んだ例は0で、後続軌道の変化による。"
              "近接試験は途中で球をリスポーンさせず、判定位置への初回到達を観測した。"
              "落下の増加を不具合と断定はしないが、返球機会・操作感の判断材料として残す。", "",
              "1球/20球の360更新は3構成とも完走、未解消・上限到達0。20球の最大補正は全構成2.84073 pxで、"
              "この6秒試験では深い解除時重なりの差を評価できていない。", "",
              "## CPU：使える測定と使わない測定", "",
              "長期の近接実行を診断なし版で比較する試みでは、225軌道中29軌道に位置差が生じ、厳しい位置/速度照合54件が不一致。"
              "終了位置差の最大は0.86345 px、速度差最大8.34573 px/sだった。"
              "同じ観測付き監査同士でも別実行で位置差があり、現行解除の前回比較で最大0.86345 pxを観測した。"
              "差の原因は未特定で、診断なし版固有の問題と断定しない。この長期CPU試行の時間は採用判断に使わない。", "",
              "代わりに、毎回まったく同じ初期位置・速度へ戻す1更新の補助測定を実施した。"
              "履歴・面分類・周囲の観測ログは外し、安全に必要な照会は含めた。"
              "比較する全入力で未解消終了0、診断版との終了位置0.001 px未満・速度0.01 px/s未満の一致を確認。"
              "8巡中1巡をウォームアップとして除外し、方式順を巡回した。", "",
              "| 同じ1,152入力・3構成とも処理完了 | 平均 µs | 中央値 µs | p95 µs | p99 µs |",
              "| --- | ---: | ---: | ---: | ---: |"]
    for mode, label in zip(MODES, LABELS):
        row = s["cpu_common"][mode]
        lines.append(f'| {label} | {row["mean_us"]:.2f} | {row["median_us"]:g} | {row["p95_us"]:g} | {row["p99_us"]:g} |')
    lines += ["", "| 同じ1,728入力・両構成とも処理完了 | 平均 µs | 中央値 µs | p95 µs | p99 µs |",
              "| --- | ---: | ---: | ---: | ---: |"]
    for mode in ("baseline", "unlimited"):
        row = s["cpu_all"][mode]
        lines.append(f'| {LABELS[MODES.index(mode)]} | {row["mean_us"]:.2f} | {row["median_us"]:g} | {row["p95_us"]:g} | {row["p99_us"]:g} |')
    lines += ["", "これは解除時の孤立した1更新のCPU負荷であり、ゲーム全体・近接Enemy全体の負荷改善を証明しない。"
              "失敗した12 px方式の576入力を3方式比較に混ぜていない。正確性・副作用の採用要件が未達のため、"
              "この補助値の改善だけで採用しない。", "",
              "## 検証・再現・資料", "",
              f'精度/統合の機械検査{s["audit_checks"]:,}件と1更新CPUの検査{s["step_cpu_checks"]:,}件、'
              '既存migration回帰96件は失敗0。長期CPU再現検査の54不一致は別記録として保持し、合格件数へ含めない。'
              '本番8ファイルのSHA-256を実行前後・最終集計で照合した。', "",
              "Godot AIの描画付き再現は4配置×3構成＝12条件でCLIの終了位置・速度・未解消・上限到達・最大補正と一致。"
              "Pで停止してNで1更新進める操作も確認し、249 px補正の前後を保存した。確認後は実行停止した。", "",
              "```powershell",
              "godot --headless --fixed-fps 60 --path . --script res://experiments/flippers/tests/unlimited_audit.gd",
              "godot --headless --fixed-fps 60 --path . --script res://experiments/flippers/tests/unlimited_step_benchmark.gd",
              "godot --headless --path . --script res://pinball/tests/migration_test.gd",
              "python experiments/flippers/tests/summarize_unlimited_audit.py", "```", "",
              "実験シーンは`unlimited_preview.tscn`。1＝現行解除、2＝12 px、3＝距離制限なし。"
              "4/5/6＝既知3配置、7＝249 px補正例を各1秒再現。P＝停止/再開、N＝停止中に1更新、R＝通常状態へ戻す。"
              "初期値は現行解除。距離制限なしの自然さはこの画面で確認できるが、今回の自動試験だけでは承認済みと扱わない。", "",
              "- [全解除入力](unlimited_grid.json)、[近接・複数球・全更新の軌道](unlimited_audit.json)。",
              "- [1更新CPU生データ](unlimited_step_benchmark.json)、[描画付き再現](unlimited_runtime.json)、[集計](unlimited_audit_summary.json)。",
              "- [比較に使わない長期CPU再現診断](unlimited_benchmark.json)。`--verify`で再現する。失敗時は終了コード1が想定される。",
              "- [前回の回復比較](release_audit.md)、[実験仕様](../shot_rules.md)。", "",
              "詳細と実験ソース・再現入力・画像は、SHA-256付きの同一一式をDesktopにも保存する。", ""]
    (E / "unlimited_audit.md").write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
