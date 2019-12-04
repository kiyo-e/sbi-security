module Sbi::Security
  class MarginStock
    include Decorator
    include Virtus.model(strict: true)

    attribute :code, Integer
    attribute :name, String
    attribute :quantity

  end
end
