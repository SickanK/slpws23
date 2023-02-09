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
  rescue Exception => e
    @errors = {} if clear_errors
    @errors[key] = e.message
  end

  def error(key, clear_errors = false)
    yield(key)
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
