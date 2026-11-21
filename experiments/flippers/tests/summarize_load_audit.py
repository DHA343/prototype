"""Validate the load experiment and summarize timings without conflating trajectories."""

import collections
import json
import math
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "evidence"
NAMES = ("empty", "flippers", "ball", "enemies10", "enemies30", "enemies60", "multiball")
LABELS = ("空環境", "操作のみ", "1球・敵0", "1球・敵10開始", "1球・敵30開始", "1球・敵60開始", "20球・敵30開始")
STAGES = ("routes_us", "flippers_us", "enemy_prepare_us", "crowd_us", "enemy_move_us", "balls_us",
          "exits_spawner_us", "launcher_us", "guide_us")


def read(name):
    return json.loads((EVIDENCE / name).read_text(encoding="utf-8"))


def stats(values):
    values = sorted(values)
    if not values:
        return None
    return {"count": len(values), "mean": statistics.mean(values), "median": statistics.median(values),
            "p95": values[math.ceil(len(values) * .95) - 1],
            "p99": values[math.ceil(len(values) * .99) - 1], "max": max(values)}


def key(row):
    return row["config"]["name"], row["mode"], row["run"]


def select(document, name, mode):
    return [r for r in document["cases"] if r["config"]["name"] == name and r["mode"] == mode]


def frame_stats(rows):
    frames = [f for r in rows for f in r["frames"]]
    exact = [f for r in rows for f in r["frames"]
             if f["enemies_start"] == f["enemies_end"] == r["config"]["enemies"]]
    strata = collections.defaultdict(list)
    for frame in frames:
        if frame["enemies_start"] == frame["enemies_end"]:
            strata[frame["enemies_start"]].append(frame["app_us"])
    return {"app_us": stats([f["app_us"] for f in frames]),
            "exact_initial_count_us": stats([f["app_us"] for f in exact]),
            "actual_count_strata_us": {str(n): stats(v) for n, v in sorted(strata.items())},
            "actual_enemy_range": [min(f["enemies_start"] for f in frames), max(f["enemies_start"] for f in frames)],
            "per_run_us": [stats([f["app_us"] for f in r["frames"]]) for r in rows],
            "outcomes": [r["outcome"] for r in rows],
            "physics_monitor_unique_values": len({f.get("engine_physics_us") for f in frames})}


def main():
    total = read("load_total.json")
    stage = read("load_headless.json")
    profile = read("load_profile.json")
    rendered = read("load_rendered.json")
    snapshot = read("load_snapshot.json")
    stability = read("load_stability.json")
    for document in (total, stage, profile, rendered, snapshot, stability):
        assert document["automatic_updates_disabled"], "Outdated double-update trial data"
    for document in (total, stage, profile, rendered):
        assert document["results_complete"]
        assert len(document["cases"]) == 14 * document["rounds"]
        assert len({key(r) for r in document["cases"]}) == len(document["cases"])
        for row in document["cases"]:
            assert len(row["frames"]) == document["samples"]
            assert len(row["initial_enemies"]) == row["config"]["enemies"]
            assert row["frames"][0]["enemies_start"] == row["config"]["enemies"]
            assert all(math.isfinite(f["app_us"]) and f["app_us"] >= 0 for f in row["frames"])
    assert snapshot["failures"] == 0 and len(snapshot["cases"]) == 19768
    reference = {key(r): r for r in total["cases"]}
    matches = {"stage": [], "profile": []}
    for label, document in (("stage", stage), ("profile", profile)):
        for row in document["cases"]:
            before = reference[key(row)]
            assert before["initial_enemies"] == row["initial_enemies"]
            # Timing hooks must not change the simulated result.
            if before["outcome"] != row["outcome"]:
                matches[label].append(key(row))
    assert all(k[0] == "multiball" for values in matches.values() for k in values), \
        "Single-ball trajectory differs between instruments"
    result = {"date": "2026-11-22", "failures": 0,
              "environment": {"cpu": total["cpu"], "gpu": rendered["gpu"],
                              "godot": total["godot"], "viewport": rendered["viewport"],
                              "render_method": rendered["render_method"], "vsync": rendered["vsync"]},
              "total": {}, "stages": {}, "profile": {}, "rendered": {}, "snapshot": {},
              "instrumentation_outcome_differences": matches, "stability": stability,
              "repeat_outcome_variants": {
                  f"{name}:{mode}": len({str(r["outcome"]) for r in select(total, name, mode)})
                  for name in NAMES for mode in (0, 4)},
              "counts": {"total_updates": sum(len(r["frames"]) for r in total["cases"]),
                         "stage_updates": sum(len(r["frames"]) for r in stage["cases"]),
                         "profile_updates": sum(len(r["frames"]) for r in profile["cases"]),
                         "rendered_updates": sum(len(r["frames"]) for r in rendered["cases"]),
                         "snapshot_updates": len(snapshot["cases"]), "snapshot_checks": snapshot["checks"]}}
    for name in NAMES:
        for mode in (0, 4):
            identity = f"{name}:{mode}"
            rows = select(total, name, mode)
            result["total"][identity] = frame_stats(rows)
            rows = select(stage, name, mode)
            result["stages"][identity] = {
                k: stats([f[k] for r in rows for f in r["frames"]]) for k in STAGES + ("app_us",)}
            rows = select(profile, name, mode)
            frames = [f for r in rows for f in r["frames"]]
            sums = {k: sum(f[k] for f in frames) for k in ("app_us", "detection_us", "separation_us", "sweep_queries",
                    "ball_geometry_checks", "guide_geometry_checks", "separation_checks", "extra_checks",
                    "contacts", "native_queries", "caps", "discarded_us")}
            result["profile"][identity] = {
                "sums": sums, "detection_percent": 100 * sums["detection_us"] / sums["app_us"],
                "separation_percent": 100 * sums["separation_us"] / sums["app_us"],
                "max_correction_px": max(f["max_correction_px"] for f in frames),
                "contactful_sweep_us": stats([f["detection_us"] for f in frames if f["ball_geometry_checks"] > 0]),
                "caps": [{"run": r["run"], "frame": f["frame"], "actual_enemies": f["enemies_start"],
                          "contacts": f["contacts"], "discarded_us": f["discarded_us"]}
                         for r in rows for f in r["frames"] if f["caps"]],
                "stages_mean_us": {k: statistics.mean(f[k] for f in frames) for k in STAGES}}
            rows = select(rendered, name, mode)
            result["rendered"][identity] = frame_stats(rows)
            draw_frames = [f for r in rows for f in r["draw_frames"]]
            assert len(draw_frames) > 0
            result["rendered"][identity]["wall_frame_us"] = stats([f["wall_us"] for f in draw_frames])
            result["rendered"][identity]["draw_calls"] = stats([f["draw_calls"] for f in draw_frames])
    for count in (0, 10, 30, 60):
        for mode in (0, 4):
            rows = [r for r in snapshot["cases"] if r["enemies"] == count and r["mode"] == mode]
            assert len(rows) == 353 * 7
            result["snapshot"][f"{count}:{mode}"] = stats([r["ball_update_us"] for r in rows])
    # With frozen bodies, changing the number of remote enemies must not alter the ball's outcome.
    frozen = collections.defaultdict(list)
    for row in snapshot["cases"]:
        frozen[(row["suite"], row["id"], row["rate"], row["mode"])].append(row)
    for rows in frozen.values():
        assert all(math.dist(r["position"], rows[0]["position"]) < .001
                   and math.dist(r["velocity"], rows[0]["velocity"]) < .01 for r in rows)
    for case in stability["cases"]:
        rows = select(profile, f"enemies{case['initial_enemies']}", case["mode"])
        expected = [(f["frame"], f["discarded_us"]) for f in rows[0]["frames"] if f["caps"]]
        actual = [(c["frame"], c["discarded_us"]) for c in case["caps"]]
        assert expected == actual, "Focused stability replay did not reproduce the profile"
        assert abs(case["max_correction"]["distance"] -
                   max(f["max_correction_px"] for f in rows[0]["frames"])) < .000001
        assert case["outcome"] == rows[0]["outcome"]
    (EVIDENCE / "load_audit_summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_report(result)
    print("Load audit validation passed.")
    for name in NAMES:
        print(name, {m: result["total"][f"{name}:{m}"]["app_us"] for m in (0, 4)})


def ms(value):
    return f"{value / 1000:.3f}"


def write_report(s):
    env = s["environment"]
    lines = ["# 基礎負荷・敵数別負荷・B/B＋4の性能監査（2026-11-22）", "",
             "## 結論", "",
             "このPCでは、B＋4の直接的な追加コストより、敵の集団処理・移動、予測ガイド、複数球時の球・ミサイル処理の影響が大きい。"
             "CPU負荷だけを理由にB＋4を退ける根拠は今回の範囲では弱い。一方、接触後の補正と移動打ち切りは別の採用条件として残る。"
             "本番Bを維持し、今回も採用変更・最適化は行っていない。", "",
             "## 環境と測定方法", "",
             f"- Godot {env['godot']['string']} / Windows、{env['cpu']}、{env['gpu']}。描画はForward Plus、1920×1080、mainの640×360レイヤーを維持。",
             "- 60 Hz。空環境、操作のみ、1球＋敵0/10/30/60開始、20球＋敵30開始の7条件をBとB＋4で比較。"
             "敵の自動生成だけ停止し、壁・バンパー・経路探索・集団処理・ダメージ・退出・ミサイル・音・予測ガイドを残した。",
             "- 同じ初期配置と入力、固定シードを使用。球は壁・バンパーと初期重なりがないことを確認し、敵はmainの生成可否条件で配置。"
             "球同士の接触は無効。敵の最大想定数は未指定のため、10/30/60は測定用の段階として扱う。",
             "- 各ケース60更新ウォームアップ後、同じ初期状態へ戻して測定。ウォームアップ・再配置・Navigation map待機・ファイル出力は時間に含めない。"
             "初回の敵準備も配置時に実行。headlessは各方式5回×240更新、描画込みは3回×180更新。方式の順を反復ごとに交代。",
             "- 敵の死亡・退出は通常どおり実行し、補充しない。測定開始時の数、毎更新の開始／終了実敵数、死亡・退出数を保存した。",
             "- 総時間の主データは段階タイマ・接触フックを入れず、main.advance＋予測ガイドを外側から計時したもの。"
             "20球だけmainと同じ順序で球ループを拡張する。球0個は参照用ノードを非表示・非衝突・非活動にし、復活を止める。",
             "- 別の実行で段階別タイマ、さらに別の実行で接触計数・反復履歴を追加した。"
             "空環境～1球・敵60の60ケースは総時間版と終了位置・速度・敵数が一致。"
             "20球では同じ方式・シードの反復でも軌道が分岐し、計測版間の不一致も残るため、内訳と総時間の対応は参考値とする。",
             "- Nodeがツリーへ入った後にmainとShotGuideの自動更新を止めることをassertで確認。初期の二重更新があった試走データは全て再測定し、集計から除外した。", "",
             "時間はTime.get_ticks_usecによるCPU経過時間。以下の『更新本体』はmainのゲーム更新とガイドの範囲であり、"
             "PhysicsServer全体・描画・音声スレッドを合わせた完全なエンジン物理フレーム時間ではない。"
             "GodotのTIME_PHYSICS_PROCESSも記録したが、モニター値に更新遅延があり、毎更新のp95/p99の根拠には使わない。"
             "[公式Performance説明](https://docs.godotengine.org/en/latest/classes/class_performance.html)も参照。", "",
             "## 更新本体のCPU時間（headless、計測フックなし）", "",
             "各方式・条件1,200更新の分布。単位ms。敵あり条件は『開始時の敵数』による連続実行の集計であり、常時同数の測定ではない。", "",
             "| 条件 | B 中央値 | B p95 | B p99 | B 最大 | B＋4 中央値 | B＋4 p95 | B＋4 p99 | B＋4 最大 |",
             "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for name, label in zip(NAMES, LABELS):
        values = [s["total"][f"{name}:{m}"]["app_us"] for m in (0, 4)]
        lines.append(f"| {label} | " + " | ".join(ms(v[k]) for v in values for k in ("median", "p95", "p99", "max")) + " |")
    peak = max(s["total"][k]["app_us"]["max"] for k in s["total"])
    lines += ["", f"全条件の観測最大は{ms(peak)} ms。60 Hzの16.667 msに対して更新本体のCPU時間には余裕があった。"
              "これは対象PC・今回の密度・入力での観測で、端末全般の性能保証やGPUを含む時間保証ではない。", "",
              "### 実際に指定数が維持されていた更新", "",
              "開始・終了とも指定数だった更新のみ。Nが多い条件ほど早期に死亡・退出して標本が少ない。"
              "この表は固定密度の定常負荷と同義ではなく、後半の敵0体を混ぜて高負荷条件を軽く見せないための区分。", "",
              "| 条件 | B 実敵数範囲 | B 指定数の標本数 / 中央値ms | B＋4 実敵数範囲 | B＋4 指定数の標本数 / 中央値ms |",
              "| --- | --- | ---: | --- | ---: |"]
    for name, label in zip(NAMES[3:], LABELS[3:]):
        a, b = (s["total"][f"{name}:{m}"] for m in (0, 4))
        ea, eb = a["exact_initial_count_us"], b["exact_initial_count_us"]
        lines.append(f"| {label} | {a['actual_enemy_range']} | {ea['count']} / {ms(ea['median'])} | "
                     f"{b['actual_enemy_range']} | {eb['count']} / {ms(eb['median'])} |")
    lines += ["", "実敵数ごとの分布は集計JSONの actual_count_strata_us に全て保存。"
              "BとB＋4で軌道・撃破数・ミサイル数が変わるため、この連続実行の時間差をそのまま絞り込み4回の純粋な費用とはしない。", "",
              "## 同じ状態からの一更新比較", "",
              "現設定336入力（60 Hz）＋既知の打球状態不一致17件＝353入力を、遠方に置いた実Enemy 0/10/30/60体の"
              "各環境で実行。球の初期位置・速度・フリッパー姿勢・入力は方式間で同一。"
              "Enemyの移動はこの比較では行わず、各試行で健康状態・速度・ガード等を戻す。準備を除いた球のadvance全体を計時。"
              "1回ウォームアップ＋7回、計19,768更新。返球・分離・反復は本番のまま。", "",
              "| 固定された敵の数 | B 中央値 µs | B＋4 中央値 µs | 差 µs | B p99 µs | B＋4 p99 µs |",
              "| ---: | ---: | ---: | ---: | ---: | ---: |"]
    for count in (0, 10, 30, 60):
        a, b = (s["snapshot"][f"{count}:{m}"] for m in (0, 4))
        lines.append(f"| {count} | {a['median']:.1f} | {b['median']:.1f} | {b['median']-a['median']:.1f} | {a['p99']:.1f} | {b['p99']:.1f} |")
    lines += ["", "遠方の敵の数を変えても、同じ入力・方式の球の終了位置／速度は一致した。"
              "この試験が切り分けるのは球更新方式と物理クエリの直接費用で、敵の経路探索・集団処理を含む固定敵数の一更新試験ではない。", "",
              "## 処理時間の内訳", "",
              "次表は接触フックなしの段階計測で、全更新の平均µs。中央値を足し合わせて全体時間にすることはしない。"
              "各列は同じ更新内の排他的な区間。段階タイマの辞書操作等も含むため、総時間版との差は計測負荷として扱う。", "",
              "| 条件・方式 | 経路refresh | 板計画・更新 | 敵準備・経路 | 集団処理 | 敵移動 | 球更新 | 退出・生成器 | ミサイル | 予測ガイド |",
              "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for name in ("ball", "enemies10", "enemies30", "enemies60", "multiball"):
        for mode in (0, 4):
            row = s["stages"][f"{name}:{mode}"]
            lines.append(f"| {LABELS[NAMES.index(name)]} {'B' if mode == 0 else 'B＋4'} | " +
                         " | ".join(f"{row[k]['mean']:.2f}" for k in STAGES) + " |")
    lines += ["", "敵準備には実際の経路検索を含む。敵数・密集度・再探索の周期が重なるため、数に比例するとは仮定していない。"
              "予測ガイドは本番のpredict_shotを維持し、B＋4でもガイド自体は現行Bのまま。"
              "ガイドは接触検出専用ではないので、その全時間をフリッパー接触検出時間とは呼ばない。", "",
              "### 球のフリッパー検出と分離", "",
              "以下は詳細フック付きの別実行。球のsweep計時は大域除外も含み、標準の停止中判定と予測ガイドは含まない。"
              "分離は別に計時するためsweepに重複しない。計数・応答履歴の負荷があるので、占有率はこの詳細実行内での参考値。", "",
              "| 条件・方式 | 球sweepの占有率 | 分離の占有率 | 幾何接触計算回数 | 分離内計算回数 | 接触処理回数 | 最大補正px |",
              "| --- | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for name in ("ball", "enemies30", "enemies60", "multiball"):
        for mode in (0, 4):
            p = s["profile"][f"{name}:{mode}"]
            lines.append(f"| {LABELS[NAMES.index(name)]} {'B' if mode == 0 else 'B＋4'} | {p['detection_percent']:.2f}% | "
                         f"{p['separation_percent']:.2f}% | {p['sums']['ball_geometry_checks']:,} | {p['sums']['separation_checks']:,} | "
                         f"{p['sums']['contacts']:,} | {p['max_correction_px']:.3f} |")
    lines += ["", "接触処理回数は実際に応答へ入った回数。標準クエリ回数は既存Recorderからの推定値として生データへ保存。"
              "球の検査、ガイドの検査、分離内の検査を区別している。B＋4の追加計算回数も各更新のextra_checksに保存。", "",
              "敵60体開始ではB＋4の追加絞り込みと上向き分離がともに0回だった。"
              "この条件の低い追加コストから『板付近で接触を反復する密集条件でも軽い』とは推論しない。"
              "実際に絞り込む費用は一更新比較と複数球の接触回数で補う。", "",
              "## 安定性", "",
              "詳細フック版の各条件1,200更新での値。打ち切りは『球1個が1更新で上限8接触に達して残り時間を破棄』を1件とする。"
              "複数球では同じ世界更新内に複数件を含み得る。", "",
              "| 条件・方式 | 打ち切り件数 | 破棄時間合計ms | 最大位置補正px |",
              "| --- | ---: | ---: | ---: |"]
    for name in NAMES[2:]:
        for mode in (0, 4):
            p = s["profile"][f"{name}:{mode}"]
            lines.append(f"| {LABELS[NAMES.index(name)]} {'B' if mode == 0 else 'B＋4'} | {p['sums']['caps']} | "
                         f"{p['sums']['discarded_us']/1000:.6f} | {p['max_correction_px']:.3f} |")
    lines += ["", "今回の修正後の60 Hz連続試験では両方式とも打ち切り0だった。"
              "30体・60体開始は別途同じ状態から再現し、最初の反復と同じ結果・最大補正を保存した。"
              "以前の30 Hzでの3条件や近接Enemyの既知の打ち切りは今回解決したとは扱わない。"
              "打ち切りとCPU時間超過は別の問題であり、今回負荷が小さかったことは反復処理の安全性の証明にはならない。", "",
              "## 通常描画を伴う実行", "",
              "Godot AIから専用シーンを起動し、通常のmainの描画・音声・ミサイル表示を伴って3反復実行した。"
              "測定中のgame_evalは行わず、全ケース完了後に完了状態を確認して停止した。"
              "フレーム時間は_process開始時刻の差で、描画待ち・OSのスケジューリング等を含む実経過時間。GPU専用タイマではない。", "",
              "| 条件・方式 | フレーム中央値ms | p95 ms | p99 ms | 最大ms |",
              "| --- | ---: | ---: | ---: | ---: |"]
    for name, label in zip(NAMES, LABELS):
        for mode in (0, 4):
            d = s["rendered"][f"{name}:{mode}"]["wall_frame_us"]
            lines.append(f"| {label} {'B' if mode == 0 else 'B＋4'} | " +
                         " | ".join(ms(d[k]) for k in ("median", "p95", "p99", "max")) + " |")
    lines += ["", "headlessのCPU時間と描画込みの実フレーム時間は別の測定なので直接引き算しない。"
              "フレーム周期には表示同期やEditor実行環境も影響し、B/B＋4の差をGPUコストの差とは断定できない。"
              "実敵数・ミサイル数・描画回数も保存し、同じ数の物体が常に描かれているという前提を置かない。", "",
              "## 判断", "",
              "1. 現行Bの球フリッパー検出は、今回のゲーム更新全体を支配する負荷ではなかった。予測ガイドの費用は別に存在する。",
              "2. B＋4の追加費用は同じ状態の一更新で確認できた。対象PCの60 Hz予算では候補に残せるが、"
              "実ゲームの目標最大数・対象端末・許容するp99は未指定のため、普遍的な『許容済み』とはしない。",
              "3. 敵数の増加に対するCPU改善を狙うなら、今回の内訳では集団処理・敵移動・再探索を先に調べる価値がある。"
              "フリッパー検出の候補除外Cを今すぐ追加する判断はしない。",
              "4. B＋4の採否については、性能より接触後の安定性が残る。上向き分離・再接触・残り時間の扱いは別課題として維持する。", "",
              "最大補正量・打ち切り件数が多いことと、CPU占有率が高いことは別である。"
              "敵30体・20球を維持し続ける定常負荷、30/120 Hz、異なる機種、敵・球の上限は今回追加していない。"
              "死亡・退出で実敵数が変わる通常挙動と、遠方の敵を固定した一更新試験の範囲を超えて結論しない。", "",
              "## 再実行・詳細資料", "",
              f"保存データの整合確認は失敗0。総時間・段階・詳細各{s['counts']['total_updates']:,}更新、"
              f"描画{s['counts']['rendered_updates']:,}更新、同一状態{s['counts']['snapshot_updates']:,}更新を保存。"
              f"単発比較の検査{s['counts']['snapshot_checks']:,}件と既存migration回帰96件は失敗0。", "",
              "CLIでは既存ポストプロセスのUID警告3件があり、パスで読込を継続した。"
              "補助の安定性診断を終了した時には音声WAV2件などのリソース残留も報告された。"
              "診断の保存結果と通常の詳細計測の終了状態・最大補正は一致したが、音声の終了処理自体は今回修正していない。"
              "本番コード・addons・シーン設定の変更はしていない。", "",
              "```powershell",
              "godot --headless --fixed-fps 60 --path . res://experiments/flippers/load_total.tscn",
              "godot --headless --fixed-fps 60 --path . res://experiments/flippers/load_audit.tscn",
              "godot --headless --fixed-fps 60 --path . res://experiments/flippers/load_audit.tscn -- --profile",
              "godot --headless --fixed-fps 60 --path . --script res://experiments/flippers/tests/load_snapshot.gd",
              "godot --headless --fixed-fps 60 --path . --script res://experiments/flippers/tests/load_stability.gd",
              "python experiments/flippers/tests/summarize_load_audit.py", "```", "",
              "描画込みはGodot AIでload_audit.tscnをcustom/ autosave=falseで起動し、"
              "evidence/load_rendered.jsonの生成後に完了状態を確認して停止する。測定中に別のベンチマークを並走させない。", "",
              "- [総時間の生データ](load_total.json)",
              "- [段階別タイマの生データ](load_headless.json)",
              "- [接触回数・分離・反復の生データ](load_profile.json)",
              "- [描画込みの生データ](load_rendered.json)",
              "- [同じ状態の球一更新](load_snapshot.json)",
              "- [反復上限・最大補正の再現履歴](load_stability.json)",
              "- [全分布・実敵数別・計測器照合の集計](load_audit_summary.json)",
              "- [既存回帰検査の記録](load_regression.log)",
              "- [補助診断の終了時記録](load_stability.log)",
              "- [計測シーンのスクリプト](../tests/load_audit.gd)",
              "- [集計スクリプト](../tests/summarize_load_audit.py)", ""]
    (EVIDENCE / "load_audit.md").write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
