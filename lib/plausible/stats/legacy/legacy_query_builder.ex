defmodule Plausible.Stats.Legacy.QueryBuilder do
  @moduledoc false

  use Plausible

  alias Plausible.Stats.{Filters, Interval, Query}

  def from(site, params) do
    now = NaiveDateTime.utc_now(:second)

    tz = time_zone(site, params)

    query =
      Query
      |> struct!(now: now, timezone: tz)
      |> put_period(site, tz, params)
      |> put_dimensions(params)
      |> put_interval(params)
      |> put_parsed_filters(params)
      |> Query.put_experimental_reduced_joins(site, params)
      |> Query.put_imported_opts(site, params)

    on_ee do
      query = Plausible.Stats.Sampling.put_threshold(query, params)
    end

    query
  end

  defp put_period(query, _site, tz, %{"period" => "realtime"}) do
    date = today(tz)

    struct!(query, period: "realtime", date_range: Date.range(date, date))
  end

  defp put_period(query, _site, tz, %{"period" => "day"} = params) do
    date = parse_single_date(tz, params)

    struct!(query, period: "day", date_range: Date.range(date, date))
  end

  defp put_period(query, _site, tz, %{"period" => "7d"} = params) do
    end_date = parse_single_date(tz, params)
    start_date = end_date |> Timex.shift(days: -6)

    struct!(
      query,
      period: "7d",
      date_range: Date.range(start_date, end_date)
    )
  end

  defp put_period(query, _site, tz, %{"period" => "30d"} = params) do
    end_date = parse_single_date(tz, params)
    start_date = end_date |> Timex.shift(days: -30)

    struct!(query, period: "30d", date_range: Date.range(start_date, end_date))
  end

  defp put_period(query, _site, tz, %{"period" => "month"} = params) do
    date = parse_single_date(tz, params)

    start_date = Timex.beginning_of_month(date)
    end_date = Timex.end_of_month(date)

    struct!(query,
      period: "month",
      date_range: Date.range(start_date, end_date)
    )
  end

  defp put_period(query, _site, tz, %{"period" => "6mo"} = params) do
    end_date =
      parse_single_date(tz, params)
      |> Timex.end_of_month()

    start_date =
      Timex.shift(end_date, months: -5)
      |> Timex.beginning_of_month()

    struct!(query,
      period: "6mo",
      date_range: Date.range(start_date, end_date)
    )
  end

  defp put_period(query, _site, tz, %{"period" => "12mo"} = params) do
    end_date =
      parse_single_date(tz, params)
      |> Timex.end_of_month()

    start_date =
      Timex.shift(end_date, months: -11)
      |> Timex.beginning_of_month()

    struct!(query,
      period: "12mo",
      date_range: Date.range(start_date, end_date)
    )
  end

  defp put_period(query, _site, tz, %{"period" => "year"} = params) do
    end_date =
      parse_single_date(tz, params)
      |> Timex.end_of_year()

    start_date = Timex.beginning_of_year(end_date)

    struct!(query,
      period: "year",
      date_range: Date.range(start_date, end_date)
    )
  end

  defp put_period(query, site, tz, %{"period" => "all"}) do
    now = today(tz)
    start_date = Plausible.Sites.stats_start_date(site) || now

    struct!(query,
      period: "all",
      date_range: Date.range(start_date, now)
    )
  end

  defp put_period(query, site, tz, %{"period" => "custom", "from" => from, "to" => to} = params) do
    new_params =
      params
      |> Map.drop(["from", "to"])
      |> Map.put("date", Enum.join([from, to], ","))

    put_period(query, site, tz, new_params)
  end

  defp put_period(query, _site, _tz, %{"period" => "custom", "date" => date}) do
    [from, to] = String.split(date, ",")
    from_date = Date.from_iso8601!(String.trim(from))
    to_date = Date.from_iso8601!(String.trim(to))

    struct!(query,
      period: "custom",
      date_range: Date.range(from_date, to_date)
    )
  end

  defp put_period(query, site, tz, params) do
    put_period(query, site, tz, Map.merge(params, %{"period" => "30d"}))
  end

  defp put_dimensions(query, params) do
    if not is_nil(params["property"]) do
      struct!(query, dimensions: [params["property"]])
    else
      struct!(query, dimensions: Map.get(params, "dimensions", []))
    end
  end

  defp put_interval(%{:period => "all"} = query, params) do
    interval = Map.get(params, "interval", Interval.default_for_date_range(query.date_range))
    struct!(query, interval: interval)
  end

  defp put_interval(query, params) do
    interval = Map.get(params, "interval", Interval.default_for_period(query.period))
    struct!(query, interval: interval)
  end

  defp put_parsed_filters(query, params) do
    struct!(query, filters: Filters.parse(params["filters"]))
  end

  defp time_zone(site, params) do
    Map.get(params, "timezone", site.timezone)
  end

  defp today(tz) do
    Timex.now(tz) |> Timex.to_date()
  end

  defp parse_single_date(tz, params) do
    case params["date"] do
      "today" -> Timex.now(tz) |> Timex.to_date()
      date when is_binary(date) -> Date.from_iso8601!(date)
      _ -> today(tz)
    end
  end
end
