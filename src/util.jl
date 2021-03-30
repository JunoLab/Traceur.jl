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
                old_logger = global_logger()
                global_logger(Logging.ConsoleLogger(Core.stderr, Logging.min_enabled_level(old_logger)))
                ret = $(esc(macrocall))
                global_logger(old_logger)
                ret
            end
        end
    end
end