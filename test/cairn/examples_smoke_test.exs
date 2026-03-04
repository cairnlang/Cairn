defmodule Cairn.ExamplesSmokeTest do
  use ExUnit.Case, async: false

  @examples ["examples/hello_world.crn", "examples/generics.crn", "examples/collections.crn", "examples/math.crn", "examples/strings.crn", "examples/interop.crn", "examples/imports/main.crn", "examples/prelude/result_flow.crn", "examples/prelude/env_parse.crn", "examples/prelude/ini_parse.crn", "examples/prelude/web_helpers.crn", "examples/practical/all_practical.crn", "examples/practical/main.crn", "examples/practical/ledger.crn", "examples/practical/todo.crn", "examples/practical/expenses.crn", "examples/practical/cashflow.crn", "examples/practical/cashflow_alerts.crn", "examples/practical/mini_grep.crn", "examples/practical/mini_grep_verify.crn", "examples/practical/mini_env.crn", "examples/practical/mini_ini.crn", "examples/concurrency/ping_pong_types.crn", "examples/concurrency/traffic_light_types.crn", "examples/concurrency/guess_binary.crn", "examples/ambitious/orchestrator.crn", "examples/policy/approval/main.crn", "examples/policy/approval/verify.crn", "examples/web/afford_verify.crn"]

  test "curated examples run end-to-end" do
    Enum.each(@examples, fn path ->
      assert {[], _env} = Cairn.eval_file(path)
    end)
  end

  test "practical examples print expected output markers" do
    assert_output_markers("examples/collections.crn", [
      "[[1, 10], [2, 20], [3, 30]]",
      "[[1, \"red\"], [2, \"green\"]]",
      "[1, 2]",
      "{:variant, \"result\", \"Ok\", [2]}",
      "[1, 10, 2, 20, 3, 30]",
      "[[0, [2, 4]], [1, [1, 3]]]"
    ])

    assert_output_markers("examples/math.crn", [
      "sin(0)=0.0",
      "cos(0)=1.0",
      "pi=",
      "e=",
      "floor(3.7)=3.0",
      "ceil(3.2)=4.0",
      "round(3.6)=4.0",
      "exp(1)=",
      "pow(8,2)=64.0",
      "log(10)=",
      "sqrt(100)=10.0"
    ])

    assert_output_markers("examples/strings.crn", [
      "upper=HELLO",
      "lower=one two",
      "reverse=cba",
      "replace=xo xo",
      "ends=TRUE"
    ])

    assert_output_markers("examples/interop.crn", [
      "int=42",
      "float=3.14"
    ])

    assert_output_markers("examples/generics.crn", [
      "int_id=42",
      "str_id=hello",
      "keep_left=7",
      "list_len=0",
      "map_get_or=cairn"
    ])

    assert_output_markers("examples/practical/main.crn", [
      "source=examples/practical/data/scores.csv",
      "total=71",
      "avg=14",
      "VERIFY score_total: OK"
    ])

    assert_output_markers("examples/practical/ledger.crn", [
      "source=examples/practical/data/ledger.csv",
      "balance=65",
      "volume=115",
      "count=5",
      "report_ok=TRUE",
      "VERIFY ledger_balance_bounded: OK"
    ])

    assert_output_markers("examples/practical/todo.crn", [
      "source=examples/practical/data/todo.txt",
      "open=3",
      "done=2",
      "total=5",
      "done_pct=40",
      "report_ok=TRUE",
      "VERIFY todo_partition_ok: OK"
    ])

    assert_output_markers("examples/practical/expenses.crn", [
      "source=examples/practical/data/expenses.csv",
      "total=1960",
      "max=1200",
      "avg=392",
      "over_100=4",
      "report_ok=TRUE",
      "VERIFY abs_total_nonneg: OK"
    ])

    assert_output_markers("examples/practical/cashflow.crn", [
      "ledger_source=examples/practical/data/ledger.csv",
      "expenses_source=examples/practical/data/expenses.csv",
      "balance=65",
      "expenses_total=1960",
      "net_cashflow=-1895",
      "volume=115",
      "capacity=2075",
      "cashflow_score=9",
      "report_ok=TRUE",
      "VERIFY cashflow_score: OK"
    ])

    assert_output_markers("examples/practical/cashflow_alerts.crn", [
      "ledger_source=examples/practical/data/ledger.csv",
      "expenses_source=examples/practical/data/expenses.csv",
      "cashflow_score=9",
      "risk_level=2",
      "risk_label=high",
      "action=reduce_costs",
      "report_ok=TRUE",
      "VERIFY risk_level: OK"
    ])

    assert_output_markers("examples/practical/mini_grep.crn", [
      "1:Cairn",
      "5:delta Cairn"
    ])

    assert_output_markers("examples/practical/mini_grep_verify.crn", [
      "VERIFY leading_flag_count_bounded: OK"
    ])

    assert_output_markers("examples/prelude/env_parse.crn", [
      "app_name=Cairn",
      "port=4000",
      "keys=3",
      "token=abc=123"
    ])

    assert_output_markers("examples/prelude/ini_parse.crn", [
      "server_host=localhost",
      "sections=2",
      "auth_token=abc123"
    ])

    assert_output_markers("examples/prelude/web_helpers.crn", [
      "html_status=200",
      "html_headers=%{\"Content-Type\" => \"text/html; charset=utf-8\"}",
      "html_body=<h1>Cairn</h1>",
      "escaped_html=&lt;script&gt;alert(&#39;hola&#39;)&lt;/script&gt; &amp; friends",
      "missing_status=404",
      "missing_headers=%{\"Content-Type\" => \"text/plain; charset=utf-8\"}",
      "missing_body=missing",
      "method_status=405",
      "method_headers=%{\"Content-Type\" => \"text/plain; charset=utf-8\"}",
      "method_body=method not allowed",
      "unauth_status=401",
      "unauth_headers=%{\"Content-Type\" => \"text/plain; charset=utf-8\"}",
      "unauth_body=login required",
      "forbidden_status=403",
      "forbidden_headers=%{\"Content-Type\" => \"text/plain; charset=utf-8\"}",
      "forbidden_body=forbidden",
      "custom_status=200",
      "custom_headers=%{",
      "\"Content-Type\" => \"text/plain; charset=utf-8\"",
      "\"X-Demo\" => \"demo=yes\"",
      "custom_body=ok",
      "get_status=200",
      "get_headers=%{\"Content-Type\" => \"text/plain; charset=utf-8\"}",
      "get_body=<p>Home</p>",
      "post_status=405",
      "post_headers=%{\"Content-Type\" => \"text/plain; charset=utf-8\"}",
      "post_body=method not allowed",
      "route_status=200",
      "route_headers=%{\"Content-Type\" => \"text/plain; charset=utf-8\"}",
      "route_body=<p>About</p>",
      "miss_route_status=404",
      "miss_route_headers=%{\"Content-Type\" => \"text/plain; charset=utf-8\"}",
      "miss_route_body=not found",
      "guard_login=TRUE",
      "guard_missing=FALSE",
      "guard_admin=TRUE",
      "guard_forbidden=FALSE"
    ])

    assert_output_markers("examples/practical/mini_env.crn", [
      "Cairn"
    ])

    assert_output_markers("examples/practical/mini_ini.crn", [
      "4000"
    ])

    assert_output_markers("examples/ambitious/orchestrator.crn", [
      "VERIFY parsed_job_count_matches: OK",
      "orchestrator: parsed=4 jobs",
      "worker_b: failing job 3 reason=boom",
      "coordinator: restarting worker_b once",
      "reporter: completed=3",
      "reporter: failed=1",
      "reporter: restarted=1",
      "reporter: run finished"
    ])

    assert_output_markers("examples/policy/approval/main.crn", [
      "viewer_dev_read=allow",
      "operator_prod_deploy=require_approval",
      "viewer_rotate_staging=deny",
      "admin_emergency_delete=require_approval",
      "draft_to_submitted=TRUE",
      "draft_to_executed=FALSE",
      "prod_export_reason=customer data access is denied by policy"
    ])

    assert_output_markers("examples/policy/approval/verify.crn", [
      "VERIFY prod_never_less_strict_than_dev: OK",
      "VERIFY viewer_never_less_strict_than_admin: OK",
      "VERIFY customer_data_never_reduces_strictness: OK",
      "VERIFY prod_delete_never_auto_allows: OK",
      "PROVE stricter_rank_example: PROVEN",
      "PROVE prod_delete_floor_proven: PROVEN",
      "PROVE dev_read_floor_proven: PROVEN"
    ])

    assert_output_markers("examples/web/afford_verify.crn", [
      "VERIFY score_one_time_in_range: OK",
      "VERIFY score_recurring_in_range: OK",
      "VERIFY higher_one_time_cost_not_better: OK",
      "VERIFY higher_recurring_cost_not_better: OK",
      "VERIFY risk_label_known: OK",
      "PROVE score_one_time: UNKNOWN",
      "PROVE score_recurring: UNKNOWN",
      "PROVE score_from_projected_margin: PROVEN",
      "PROVE reserve_threshold: PROVEN",
      "PROVE caution_threshold: PROVEN",
      "PROVE reserve_breach_not_safe: UNKNOWN",
      "PROVE negative_margin_not_safe_from_margin: PROVEN"
    ])
  end

  defp assert_output_markers(path, markers) do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert {[], _env} = Cairn.eval_file(path)
      end)

    Enum.each(markers, fn marker ->
      assert output =~ marker
    end)
  end
end
