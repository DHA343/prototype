"""Keep aborted safe trials and postponed collision opportunities visible."""

import collections
import hashlib
import json
import math
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "evidence"
MODES = ("production", "baseline", "postpone", "safe3", "safe6", "safe12")
LABELS = ("従来B", "実験基準・現行解除", "解除延期", "安全分離3 px", "安全分離6 px", "安全分離12 px")


def read(name):
    return json.loads((EVIDENCE / name).read_text(encoding="utf-8-sig"))


def cpu(values):
    values = sorted(values)
    return {"samples": len(values), "mean_us": statistics.mean(values),
            "median_us": statistics.median(values), "p95_us": values[math.ceil(len(values)*.95)-1],
            "p99_us": values[math.ceil(len(values)*.99)-1], "max_us": max(values)}


def main():
    data, grid, benchmark = (read(name) for name in
                            ("release_audit.json", "release_grid.json", "release_benchmark.json"))
    old = read("separation_diagnostics.json")
    live = read("release_runtime.json")
    assert all(item["failures"] == 0 for item in (data, grid, benchmark))
    assert len(grid["cases"]) == 1728 and len(data["transitions"]) == 30
    assert len(data["tails"]) == 18 and len(live["results"]) == 12
    assert live["failure_stopped"] and live["reset_recovered"]
    assert len(data["contracts"]) == 7 and data["regression"] == {"cases": 4644, "variants": 6}
    for path, expected in data["production_sha256"].items():
        assert hashlib.sha256((ROOT.parents[1] / path).read_bytes()).hexdigest() == expected
        assert benchmark["production_sha256"][path] == expected
    result = {"checks": data["checks"], "benchmark_checks": benchmark["checks"], "failures": 0,
              "near": {}, "grid": {}, "cpu": {}, "legacy_contact_count_variations": [],
              "tails": data["tails"], "transitions": data["transitions"],
              "contracts": data["contracts"], "production_sha256": data["production_sha256"]}
    for mode, previous in (("production", "current"), ("baseline", "combined")):
        for before, after in zip(old["integration"][previous]["near_enemy"],
                                 data["integration"][mode]["near_enemy"], strict=True):
            for key in ("exhausted_updates", "discarded_ms", "max_correction_px", "shots"):
                assert abs(before[key] - after[key]) < .001, (mode, key)
            if before["contacts"] != after["contacts"]:
                result["legacy_contact_count_variations"].append({"mode": mode,
                    "ratio": after["ratio"], "gap": after["gap"], "offset": after["offset"],
                    "old_contacts": before["contacts"], "new_contacts": after["contacts"]})
    for mode in MODES:
        integration = data["integration"][mode]
        near = integration["near_enemy"]
        assert len(near) == 84 and len(integration["population"]) == 2
        assert all(row["completed"] == (not row["unresolved"]) for row in near)
        events = [event for row in near for event in row.get("release_events", [])]
        observed = collections.Counter()
        states = collections.Counter()
        failures = []
        for row in near:
            states.update(row["observed"]["states"])
            observed.update({key: value for key, value in row["observed"].items() if key != "states"})
            if row["unresolved"]:
                event = row["release_events"][-1]
                assert event["unresolved"] and not event["events"] and event["guard_active"]
                assert event["position"] == event["release"]["before"]
                assert event["release_correction_px"] == 0 and not event["guard_released"]
                failures.append({"ratio": row["ratio"], "gap": row["gap"], "offset": row["offset"],
                                 "attempted_update": row["updates"] - 1, "failure": event})
        successful_corrections = [event for event in events if event["release_correction_px"] > 0]
        for event in successful_corrections:
            assert event["release_correction_px"] <= event["release"]["limit_px"] + 1e-5
            assert not event["release"]["world_after"]
            assert event["release"]["candidates"][-1]["rejected"] == ""
        result["near"][mode] = {"completed": sum(row["completed"] for row in near),
            "unresolved": len(failures), "capped_inputs": sum(row["exhausted_updates"] > 0 for row in near),
            "capped_updates": sum(row["exhausted_updates"] for row in near),
            "discarded_ms": sum(row["discarded_ms"] for row in near),
            "max_correction_px": max(row["max_correction_px"] for row in near),
            "max_delay_ms": max(row["max_delay_ms"] for row in near),
            "overdue_bottom_events": sum(row["below_overdue"] for row in near),
            "overdue_bottom_inputs": sum(row["below_overdue"] > 0 for row in near),
            "still_pending": sum(bool(row.get("release_events")) and row["guard_active_at_end"]
                and row["release_events"][-1]["release"]["deferred"] for row in near),
            "release_requests": len(events), "overlap_requests": sum(event["release"]["overlapping"] for event in events),
            "shots_on_release": sum(event["shots"] for event in events if event["guard_released"]),
            "shots_total": sum(row["shots"] for row in near), "states": dict(states), "observed": dict(observed),
            "safe_corrections": len(successful_corrections), "failed_cases": failures,
            "population": integration["population"]}
        entries = [row["methods"][mode] for row in grid["cases"]]
        result["grid"][mode] = {"cases": len(entries), "unresolved": sum(row["unresolved"] for row in entries),
            "released": sum(row["guard_released"] for row in entries),
            "deferred": sum(row["release"]["deferred"] for row in entries),
            "max_correction_px": max(row["max_correction_px"] for row in entries), "by_state": {}}
        for moving in (False, True):
            selected = [row["methods"][mode] for row in grid["cases"] if row["moving"] == moving]
            result["grid"][mode]["by_state"]["moving" if moving else "stopped"] = {
                "cases": len(selected), "unresolved": sum(row["unresolved"] for row in selected),
                "max_correction_px": max(row["max_correction_px"] for row in selected)}
        if mode != "production":
            rounds = [round_["times_us"][mode] for round_ in benchmark["rounds"] if not round_["warmup"]]
            assert len(rounds) == 7 and all(len(values) == 1728 for values in rounds)
            result["cpu"][mode] = cpu([value for values in rounds for value in values])
            for failed, label in ((False, "not_aborted"), (True, "aborted")):
                indices = [i for i, row in enumerate(entries) if row["unresolved"] == failed]
                if indices:
                    result["cpu"][mode][label] = cpu([values[i] for values in rounds for i in indices])
                    result["cpu"][mode][label]["fixtures"] = len(indices)
    for row in live["results"]:
        expected_row = next(item for item in grid["cases"] if not item["moving"] and item["rate"] == 60
            and item["case"]["angle"] == 0 and item["case"]["side"] == 0 and item["case"]["feature"] == 0
            and item["case"]["radius"] == row["radius"] and item["case"]["depth"] == row["depth"])
        expected = expected_row["methods"][MODES[int(row["mode"])]]
        assert math.dist(expected["position"], row["position"]) < .001
        assert math.dist(expected["velocity"], row["velocity"]) < .01
        assert expected["unresolved"] == row["unresolved"] and expected["guard_active"] == row["guard_active"]
        assert row["exceptions"] == 0
    for row in live["controls"]:
        assert row["rules"] == ([0, 0] if row["mode"] == 0 else [2, 2])
    pending_tails = [row["result"] for row in data["tails"] if row["mode"] == "postpone"]
    assert all(row["guard_active_at_end"] and abs(row["max_delay_ms"] - 2000) < .001
               for row in pending_tails if row["case"] != "other_flipper")
    assert next(row for row in pending_tails if row["case"] == "other_flipper")["right_entry_while_disabled"] == 1
    result["runtime_matches_cli"] = True
    (EVIDENCE / "release_audit_summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    report(result)
    print("Release saved-data validation passed; aborts, bounds, previous controls, live replay and hashes verified.")
    print(json.dumps({mode: {key: value for key, value in result["near"][mode].items()
                           if key not in ("failed_cases", "population", "states", "observed")}
                      for mode in MODES}, ensure_ascii=False, indent=2))


def report(s):
    lines = ["# ③解除時の回復：現行・解除延期・小さい安全分離（2026-11-23）", "",
             "## 判断", "",
             "今回のB（解除延期）とC（安全な小補正）は、そのまま本番採用しない。解除延期は既知の打ち切りを避けるが、"
             "下降中の板下通過と長期未解除が生じる。安全分離3/6/12 pxは浅い重なりを処理できるが、"
             "既知の深い重なりを解消できず試行が終了する。途中終了を打ち切り改善と数えてはいけない。", "",
             "打球は3条件、新接触の法線分離・検出B・③の左右共通管理・上向き探索16回・共有8接触を実験基準として維持。"
             "本番のmain、PinballMotion、PinballFlippers、TableFlipper、Enemyは変更していない。", "",
             "| 構成 | 近接84配置の完走 | 未解消終了 | 接触上限へ到達した配置 | 最大補正 px |",
             "| --- | ---: | ---: | ---: | ---: |"]
    for mode, label in zip(MODES, LABELS):
        row = s["near"][mode]
        lines.append(f'| {label} | {row["completed"]} | {row["unresolved"]} | {row["capped_inputs"]} | {row["max_correction_px"]:.5f} |')
    lines += ["", "安全分離の最大値には終了前までの通常接触も含む。失敗した更新は球の位置・速度を変更せず終了し、"
              "残りの試験時間は未実行である。安全分離の『接触上限0』と現行の完走84配置を直接比較して優位とは扱わない。", "",
              "## 実装した候補の定義", "",
              "- **現行解除**：重力適用後のY速度が1 px/sを超えれば、重なりにかかわらず左右の③を解除する。",
              "- **解除延期**：既存の下降条件を満たし、両フリッパーとの幾何的接触がなくなった更新開始時に解除。"
              "待機中にEnemy等で上向きに戻った場合も、下降条件を満たすまで再有効化しない。左右別の解除は導入しない。",
              "- **安全分離**：下降条件を満たした更新開始時に、初期接触の法線方向と上下左右の有限候補を試す。"
              "上限はユーザー指定の3/6/12 px。法線候補は深さ＋0.151 px、軸方向は開始時の四角形の外接範囲から円全体が退出する距離。"
              "短い順に調べ、補正先で左右両板・周囲の物体と接触せず、補正経路も安全な最初の候補を使う。", "",
              "0.151 pxは従来の0.15 pxに丸め誤差対策0.001 pxを加えた実験値。板の補正先と物理世界の安全照会は0.03 pxの余裕を使用した。"
              "有限候補の最短であり、世界全体の最短安全位置を保証する探索ではない。", "",
              "安全な候補がない場合は、ユーザー指定どおり未解消としてその試行を終了。延期・真上への大移動へ自動切替しない。"
              "補正自体は速度・打球・③開始を発生させず、再有効化後の通常接触は共通の3条件で処理する。", "",
              "## 時刻と周囲の安全性", "",
              "③の解除フックを実験側のフリッパー管理部品へ置き、Godotの移動・位置回復クエリより前に処理した。"
              "球は更新開始位置、回転板は回転計画の開始姿勢、停止板はその姿勢を使う。更新終了姿勢との混在は避けた。"
              "Enemy・壁は現在のBが照会する物理世界を使い、Enemyの過去姿勢の復元はしていない。", "",
              "補正経路では、新規物体への進入をスイープで検査。開始重なりはスイープだけでは検出できないため、"
              "前後の照会を併用する。既存の障害物との重なりから退出する候補は許可するが、接触点対から求めた"
              "法線へ逆行する補正と、補正先に重なりを残す候補は不採用とした。開始重なりの凹形状は今回未対応として候補を棄却する。"
              "別板も開始姿勢の形状で経路検査する。照会結果128件上限では安全とせず候補を棄却する。", "",
              "照会の仕様は [Godot公式 PhysicsDirectSpaceState2D](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate2d.html)、"
              "接触点対の法線・深さは [Godot公式 Shape2D](https://docs.godotengine.org/en/stable/classes/class_shape2d.html) を参照した。"
              "補正時点の安全性を調べるもので、後続の通常移動や他物体の将来の移動まで安全を保証するものではない。", "",
              "独立した検査で、前後とも非接触の薄壁横断を棄却、開始重なりから外へ出る補正は許可、"
              "既存物体の反対側へ貫く補正は棄却することを確認した。直接回復の浅い／深い条件で、"
              "速度不変、補正上限、失敗時の位置不変と③維持も検査した。", "",
              "## 試験範囲", "",
              "| 試験 | 条件 |", "| --- | --- |",
              "| 解除時の形状・深さ | 既存開始重なり288 × 停止/回転 × 30/60/120 Hz＝1,728入力、各6構成 |",
              "| 近接Enemy | 84配置 × 6構成、各60更新。失敗した安全分離の試行はその場で終了 |",
              "| 複数球 | 1球/20球 × 6構成、各360更新。初期配置・種は前回と同じ。球同士は衝突しない |",
              "| 解除・停止境界 | 既存5状態 × 6構成＝30実行（前回の20実行を含む状態集合） |",
              "| 延期副作用 | 低速内部、途中から静止、反対側の板への進入、各2秒 × 6構成 |",
              "| 通常接触の回帰 | 既存4,644入力 × 6構成を前回保存結果と照合 |",
              "| CPU | 解除時1,728入力 × 実験5構成、8巡中1巡をウォームアップとして除外 |", "",
              "『浅い』の新たな仕様しきい値は導入せず、面・幾何的深さ・回転有無・周囲の物体を記録した。"
              "開始重なりの名目深さは0.2、3、半径＋12 px。角や深い内部では名目値と実測深さが一致しないため、実測値を使用する。", "",
              "## 形状・深さ別の結果", "",
              "| 構成 | 解除できた入力 / 1,728 | 延期中 | 未解消終了 | 停止板の未解消 / 864 | 回転板の未解消 / 864 |",
              "| --- | ---: | ---: | ---: | ---: | ---: |"]
    for mode, label in zip(MODES, LABELS):
        row = s["grid"][mode]
        lines.append(f'| {label} | {row["released"]} | {row["deferred"]} | {row["unresolved"]} | {row["by_state"]["stopped"]["unresolved"]} | {row["by_state"]["moving"]["unresolved"]} |')
    lines += ["", "解除延期はこの単独更新では全条件を通過可能のままにしており、『補正0で解消した』という結果ではない。"
              "安全分離6→12 pxにしても、この入力集合では解除できた数は増えなかった。深い内部の回復には不足する。", "",
              "## 既知3配置の原因", "",
              "| 配置（ratio / gap / offset） | 解除直前の幾何的深さ | 板 | 実験基準の結果 |",
              "| --- | ---: | --- | --- |",
              "| 0.5 / 36 / 0 | 28.48835 px、上面 | 停止 | 更新2で8接触、12.118682 ms破棄 |",
              "| 0.7 / 36 / 0 | 40.58581 px、上面 | 停止 | 更新2で8接触、13.454284 ms破棄 |",
              "| 0.9 / 3 / 0 | 24.49072 px、右側面 | 回転中 | 更新1で上向き60.60965 px補正、Enemyへ新規食い込み |", "",
              "今回はGodot回復より前の幾何的深さを記録した。停止板のGodot報告深さや回復後の残存深さとは異なる。"
              "3配置とも最も近い面への退出距離が12 pxを超えるため、承認された上限内の小補正では解消できない。"
              "近接の安全分離の全未解消ケースで、調べた候補の棄却理由は上限超過だった。探索方向を増やすだけで改善する根拠は得られていない。", "",
              "## 解除延期の副作用", "",
              f'近接84配置での最大延期は{s["near"]["postpone"]["max_delay_ms"]:.3f} ms。'
              f'下降条件を満たして延期中に板下を通過したものは{s["near"]["postpone"]["overdue_bottom_events"]}イベント、'
              f'{s["near"]["postpone"]["overdue_bottom_inputs"]}配置だった。'
              "これは今回の固定配置で観測した通過で、通常プレイの発生率でも、すべてが望ましくない通過という評価でもない。", "",
              "低速内部（重力0、Y速度2 px/s）と、初回の延期後に速度0へ固定する専用条件では、2秒後も③が解除されなかった。"
              "後者は外部から速度を固定する診断条件であり通常プレイを模した発生率試験ではないが、待機に自動終端がないことを示す。", "",
              "反対側進入の専用条件では、左板の内側端付近から右へ3,600 px/sで進めると、延期中の最初の更新で"
              "右板へ進入した。左右をまとめて無効にする副作用である。別板だけ再有効化する処理は追加していない。", "",
              "## 再打球・周囲干渉", "",
              "| 構成 | 解除した更新内の打球 | 全期間の打球 | 通常補正後の新規干渉イベント | Cの事前補正数 |",
              "| --- | ---: | ---: | ---: | ---: |"]
    for mode, label in zip(MODES, LABELS):
        row = s["near"][mode]
        lines.append(f'| {label} | {row["shots_on_release"]} | {row["shots_total"]} | {row["observed"]["E_introduced"]} | {row["safe_corrections"]} |')
    lines += ["", "これは近接84配置の観測数。打球が起きたことだけで『意図しない再打球』とは断定しない。"
              "延期は接触機会と軌道を変え、安全分離は途中終了によって観測期間を短くするため、打球数や干渉数の減少だけで精度改善とはしない。"
              "Cの事前補正は別記録で、採用した候補の補正先は周囲非接触を照会済み。新規干渉0には未実行時間の影響もある。", "",
              "1球/20球の360更新試験は全構成で完走し、接触上限・未解消は0。実験基準と候補の最大補正は20球で2.84073 px、"
              "従来Bでは58.54790 pxだった。今回の6秒試験だけで深い解除時重なりの問題がなくなったとはしない。", "",
              "## CPU負荷と照合", "",
              "イベント履歴、面分類、前後の周囲観測、候補ログを外した実験Motionで、`ball.advance()`全体を測った。"
              "安全性に必要な接触・経路照会は含む。初期化とリセットは計測外。各巡の方式順を巡回し、"
              "各構成12,096サンプル（1,728×7）を集計した。診断版との位置・速度・未解消判定の照合8,640組は一致。", "",
              "| 構成 | 平均 µs | 中央値 µs | p95 µs | p99 µs | 最大 µs |",
              "| --- | ---: | ---: | ---: | ---: | ---: |"]
    for mode, label in zip(MODES[1:], LABELS[1:]):
        row = s["cpu"][mode]
        lines.append(f'| {label} | {row["mean_us"]:.2f} | {row["median_us"]:g} | {row["p95_us"]:g} | {row["p99_us"]:g} | {row["max_us"]:g} |')
    lines += ["", "解除が毎入力で要求される負荷試験であり、通常プレイの平均負荷ではない。延期はフリッパーとの処理を省き、"
              "Cの失敗では球の移動自体を実行しない。そのため、上表の低い平均値をそのまま高速化の証拠にしない。", "",
              "| 安全分離 | 未解消にならない入力数 | その平均 µs | 未解消入力数 | 失敗判定までの平均 µs |",
              "| --- | ---: | ---: | ---: | ---: |"]
    for mode, label in zip(MODES[3:], LABELS[3:]):
        row = s["cpu"][mode]
        done, aborted = row["not_aborted"], row["aborted"]
        lines.append(f'| {label} | {done["fixtures"]} | {done["mean_us"]:.2f} | {aborted["fixtures"]} | {aborted["mean_us"]:.2f} |')
    lines += ["", "今回、通常接触の既存4,644入力は6構成とも、従来Bまたは組み合わせ案の保存位置・速度と一致した。"
              "近接の対照2構成も、全84配置の打球数・最大補正・上限到達・破棄時間は前回値と一致。"
              "ただし総接触数は各対照1配置ずつ±1イベントの差があり、前回履歴と全イベント完全一致とはしない。"
              "差の配置と件数は集計JSONに保存した。今回の同一実行内の候補比較と区別している。", "",
              f'機械検査{s["checks"]:,}件、診断なし版の照合等{s["benchmark_checks"]:,}件、'
              '既存migration回帰96件で失敗0。最終CLIログのSCRIPT ERROR/ERRORは0。'
              '本番8ファイルのSHA-256を前後と最終集計で確認した。', "",
              "Godot AIの描画付き実行でも6方式を切り替え、浅い/深い解除12ケースで位置・速度・未解消・③の状態がCLIと一致。"
              "確認後は実行停止し、mainや起動設定は保存していない。", "",
              "## 次の判断", "",
              "- 3条件と新接触の法線分離は実験基準として維持する。本番は現状維持。",
              "- 解除延期を採用するには、下降中の通過と未解除をどこまで許すかというゲーム仕様の判断が必要。",
              "- 安全な小補正は浅い重なりに限定した候補として残るが、今回の深い内部からの復帰手段にはならない。",
              "- 深い内部では『通過を継続するか、大きい補正を許すか、別の復帰規則を選ぶか』を先に決める。"
              "失敗時の暗黙フォールバックや反復上限の拡大は追加しない。", "",
              "## 再現と保存先", "",
              "```powershell",
              "godot --headless --fixed-fps 60 --path . --script res://experiments/flippers/tests/release_audit.gd",
              "godot --headless --fixed-fps 60 --path . --script res://experiments/flippers/tests/release_benchmark.gd",
              "godot --headless --path . --script res://pinball/tests/migration_test.gd",
              "python experiments/flippers/tests/summarize_release_audit.py", "```", "",
              "実験シーンは`release_preview.tscn`。1＝従来B、2＝実験基準（初期値）、3＝解除延期、4/5/6＝安全分離3/6/12 px、"
              "R＝リセット。安全分離で候補がない場合は未解消として停止表示する。A/D/Spaceは既存操作。", "",
              "- [全解除入力](release_grid.json)：1,728×6の位置・速度・面・深さ・回復・接触履歴。",
              "- [統合監査](release_audit.json)：近接・複数球・遷移・延期の副作用・独立安全検査。",
              "- [CPU生データ](release_benchmark.json)、[描画付き再現](release_runtime.json)、[集計](release_audit_summary.json)。",
              "- [前回の組み合わせ比較](separation_audit.md)、[実験仕様](../shot_rules.md)。", "",
              "詳細資料・実験ソース・必要な再現入力は、SHA-256で照合した同一一式をDesktopにも保存する。", ""]
    (EVIDENCE / "release_audit.md").write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
