class RateLimiter
  def initialize(redis, request, limit, period)
    @redis = redis
    @key = "failed_attempts:#{request.ip}"
    @limit = limit
    @period = period
  end

  def limit_exceeded?
    @redis.get(@key).to_i >= @limit
  end

  def call
    @redis.incr(@key)
    @redis.expire(@key, @period) unless limit_exceeded?
  end
end
