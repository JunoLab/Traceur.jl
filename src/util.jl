using Logging

# define safe loggers that use raw streams,
# since we can't use regular streams that lock upon use
for level in [:trace, :debug, :info, :warn, :error, :fatal]
    @eval begin
        macro $(Symbol("safe_$level"))(ex...)
            macrocall = :(@placeholder $(ex...))
            # NOTE: `@placeholder` in order to avoid hard-coding @__LINE__ etc
            macrocall.args[1] = Symbol($"@$level")
            quote
                global_min_level = Logging.min_enabled_level(global_logger())
                raw_logger = Logging.ConsoleLogger(Core.stderr, global_min_level)
                Logging.with_logger(raw_logger) do
	                global ret = $(esc(macrocall))
                end
                ret
            end
        end
    end
end
