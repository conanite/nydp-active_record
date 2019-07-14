# Nydp::ActiveRecord

Enables use of Rails' ActiveRecord objects within nydp code.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'nydp-active_record'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install nydp-active_record


You need to define #nydp_call on ActiveRecord::Base

```ruby
class ActiveRecord::Base
  def nydp_ns
    Nydp.get_nydp # or whatever you normally do to set up your nydp namespace
  end

  def nydp_call fn, *args
    Nydp.apply_function nydp_ns, fn, *args
  end
end
```


## Security

Override `self.nydp_sanitise_attrs` on ActiveRecord::Base to control which attributes are allowed through `'build`, `'update`, and `'create` functions.

By default, all persisted attributes are readable from nydp, as are tags (from acts_as_taggable_on), attachments (paperclip) and associations.

To prevent an attribute X from being read, create a `_nydp_X` method. For example, Customer has a #secret_token attribute that you want to keep secret:

```ruby
class Customer < ActiveRecord::Base
  def _nydp_secret_token
    "you can't have it"
  end
end
```

Any `customer.secret-token` request will just return "you can't have it". Normal ruby code (eg `customer.secret_token`) will continue to work as normal.

To allow a non-persistent attribute to be read, add it to `nydp_whitelist`:

```ruby
class Customer < ActiveRecord::Base
  has_many :invoices

  def needs_chasing?
    self.invoices.any? &:unpaid?
  end

  def _nydp_whitelist
    [ :needs_chasing? ]
  end
end
```

A call to `customer.needs-chasing?` will result in a call to the `#needs_chasing?` method on the Customer instance.

## Usage

Install this gem as described ; your active_record objects will be usable from inside nydp code.

To find a customer:

```lisp
(let customer (find 'customer 123) ...)
```

to create a customer:

```lisp
(let customer (create 'customer { name "Airboss" address "Toulouse" }) ...)
```

to delete a customer:

```lisp
(destroy customer)
```

to update a customer:

```lisp
(update customer { name "Airbus SA" address "31200 Toulouse, France"})
```

to display customer information:

```lisp
(let customer (find 'customer 123) (p customer.name))
```

or somewhat more sophisticatedly:

```lisp
(j:map λc(%tr (%td c.name) (%td c.address)) customers)
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/nydp-active_record. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Nydp::ActiveRecord project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/nydp-active_record/blob/master/CODE_OF_CONDUCT.md).

You will need to provide #nydp_call(fn, *args) on ActiveRecord::Base so that callbacks ('after-create 'after-save) will work
