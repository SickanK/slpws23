class ClearField < Exception
end

# Maybe add clear_field_on_error to exception in future?

class FormValidator
  attr_accessor :params, :errors, :values

  def initialize(params, errors = {}, values = {})
    @params = params
    @errors = errors
    @values = values
  end

  def validate(key, clear_errors = false)
    value = @params[key].strip
    @values[key] = value
    yield(value, key)
  rescue ClearField => e
    @errors = {} if clear_errors
    @values[key] = ""
    @errors[key] = e.message
  rescue Exception => e
    @errors = {} if clear_errors
    @errors[key] = e.message
  end

  def error(key, clear_errors = false)
    yield(key)
  rescue ClearField => e
    @errors = {} if clear_errors
    @values[key] = ""
    @errors[key] = e.message
  rescue Exception => e
    @errors = {} if clear_errors
    @errors[key] = e.message
  end

  def clear_field(key)
    @values.delete(key)
  end

  def success?
    @errors.empty?
  end
end

# Helper method to send form-response with rate limiter

def send_response(form, rate_limiter, redirect_path)
  rate_limiter.call()
  if rate_limiter.limit_exceeded?
    form.error(:General, true) do
      raise "Too many failed attempts. Please wait a moment before trying again."
    end
  end

  session[:errors] = form.errors
  session[:values] = form.values
  redirect(redirect_path)
end
