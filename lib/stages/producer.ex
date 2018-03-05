defmodule Kaufmann.Stages.Producer do
  @moduledoc """
  `GenStage` Producer to introduce backpressure between `KafkaEx.GenConsumer` and `Flow` stage in `Kaufmann.Subscriber`
  """

  require Logger
  use GenStage

  def start_link(message_set \\ []) do
    :ok = Logger.info(fn -> "#{__MODULE__} Starting" end)
    GenStage.start_link(__MODULE__, message_set, name: __MODULE__)
  end

  def init(message_set) do
    {:producer, %{message_set: message_set, demand: 0, from: nil}}
  end

  def notify(message_set, timeout \\ 5000) do
    IO.inspect(message_set)
    GenStage.call(__MODULE__, {:notify, message_set}, timeout)
  end

  # When no messages to meet demand, nothing to do
  def handle_demand(demand, %{message_set: []} = state) when demand > 0 do
    {:noreply, [], %{state | demand: demand}}
  end

  # when more messages than demand, no need to request more messages
  def handle_demand(demand, %{message_set: message_set} = state)
      when demand > 0 and length(message_set) > demand do
    {to_dispatch, remaining} = Enum.split(message_set, demand)
    {:noreply, to_dispatch, %{state | message_set: remaining, demand: 0}}
  end

  # request 
  def handle_demand(demand, %{message_set: message_set} = state) when demand > 0 do
    IO.puts("handleDemand ~ demand")
    new_state = %{state | message_set: [], demand: demand - length(message_set)}
    GenStage.reply(state.from, :ok)
    {:noreply, message_set, new_state}
  end

  # When no demand, save messages to state, wait.
  def handle_call({:notify, message_set}, from, %{demand: 0} = state) do
    IO.puts("handle call 0 demand")
    {:noreply, [], %{state | message_set: message_set, from: from}}
  end

  # When more messages than demand, dispatch to meet demand, wait for more demand
  def handle_call({:notify, message_set}, from, %{demand: demand} = state)
      when length(message_set) > demand do
    IO.puts("handle call > demand")
    {to_dispatch, remaining} = Enum.split(message_set, demand)

    new_state = %{
      state
      | message_set: remaining,
        demand: demand - length(to_dispatch),
        from: from
    }

    {:noreply, to_dispatch, new_state}
  end

  # When demand greater than message count, reply for more messages
  def handle_call({:notify, message_set}, _from, %{demand: demand} = state) do
    IO.puts("handle call ? demand")
    new_state = %{state | demand: demand - length(message_set)}

    {:reply, :ok, message_set, new_state}
  end
end
