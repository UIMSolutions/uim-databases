/*********************************************************************************************************
* Copyright: © 2015-2023 Ozan Nurettin Süel (Sicherheitsschmiede)                                        *
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.  *
* Authors: Ozan Nurettin Süel (Sicherheitsschmiede)                                                      *
**********************************************************************************************************/
module uim.databases.types.base;

@safe:
import uim.databases;

/**
 * Datetime type converter.
 *
 * Use to convert datetime instances to strings & back.
 */
class DateTimeType : BaseType, IBatchCasting
{
    /**
     * Whether we want to override the time of the converted Time objects
     * so it points to the start of the day.
     *
     * This is primarily to avoid subclasses needing to re-implement the same functionality.
     *
     * @var bool
     */
    protected $setToDateStart = false;

    /**
     * The DateTime format used when converting to string.
     *
     * @var string
     */
    protected $_format = "Y-m-d H:i:s";

    /**
     * The DateTime formats allowed by `marshal()`.
     *
     * @var array<string>
     */
    protected $_marshalFormats = [
        "Y-m-d H:i",
        "Y-m-d H:i:s",
        "Y-m-d\TH:i",
        "Y-m-d\TH:i:s",
        "Y-m-d\TH:i:sP",
    ];

    /**
     * Whether `marshal()` should use locale-aware parser with `_localeMarshalFormat`.
     *
     * @var bool
     */
    protected $_useLocaleMarshal = false;

    /**
     * The locale-aware format `marshal()` uses when `_useLocaleParser` is true.
     *
     * See `Cake\I18n\Time::parseDateTime()` for accepted formats.
     *
     * @var array|string|int
     */
    protected $_localeMarshalFormat;

    /**
     * The classname to use when creating objects.
     *
     * @var string
     * @psalm-var class-string<\DateTime>|class-string<\DateTimeImmutable>
     */
    protected $_className;

    /**
     * Database time zone.
     *
     * @var \DateTimeZone|null
     */
    protected $dbTimezone;

    /**
     * User time zone.
     *
     * @var \DateTimeZone|null
     */
    protected $userTimezone;

    /**
     * Default time zone.
     *
     * @var \DateTimeZone
     */
    protected $defaultTimezone;

    /**
     * Whether database time zone is kept when converting
     *
     * @var bool
     */
    protected $keepDatabaseTimezone = false;

    /**
     * {@inheritDoc}
     *
     * @param string|null $name The name identifying this type
     */
    public this(?string $name = null)
    {
        parent::__construct($name);

        this.defaultTimezone = new DateTimeZone(date_default_timezone_get());
        this._setClassName(FrozenTime::class, DateTimeImmutable::class);
    }

    /**
     * Convert DateTime instance into strings.
     *
     * @param mixed aValue The value to convert.
     * @param \Cake\Database\IDTBDriver aDriver The driver instance to convert with.
     * @return string|null
     */
    function toDatabase(aValue, IDTBDriver aDriver): ?string
    {
        if (aValue == null || is_string(aValue)) {
            return aValue;
        }
        if (is_int(aValue)) {
            $class = this._className;
            aValue = new $class("@" . aValue);
        }

        if (
            this.dbTimezone != null
            && this.dbTimezone->getName() != aValue->getTimezone()->getName()
        ) {
            if (!aValue instanceof DateTimeImmutable) {
                aValue = clone aValue;
            }
            aValue = aValue->setTimezone(this.dbTimezone);
        }

        return aValue->format(this._format);
    }

    /**
     * Alias for `setDatabaseTimezone()`.
     *
     * @param \DateTimeZone|string|null $timezone Database timezone.
     * @return this
     * @deprecated 4.1.0 Use {@link setDatabaseTimezone()} instead.
     */
    function setTimezone($timezone)
    {
        deprecationWarning("DateTimeType::setTimezone() is deprecated. Use setDatabaseTimezone() instead.");

        return this.setDatabaseTimezone($timezone);
    }

    /**
     * Set database timezone.
     *
     * This is the time zone used when converting database strings to DateTime
     * instances and converting DateTime instances to database strings.
     *
     * @see DateTimeType::setKeepDatabaseTimezone
     * @param \DateTimeZone|string|null $timezone Database timezone.
     * @return this
     */
    function setDatabaseTimezone($timezone)
    {
        if (is_string($timezone)) {
            $timezone = new DateTimeZone($timezone);
        }
        this.dbTimezone = $timezone;

        return this;
    }

    /**
     * Set user timezone.
     *
     * This is the time zone used when marshalling strings to DateTime instances.
     *
     * @param \DateTimeZone|string|null $timezone User timezone.
     * @return this
     */
    function setUserTimezone($timezone)
    {
        if (is_string($timezone)) {
            $timezone = new DateTimeZone($timezone);
        }
        this.userTimezone = $timezone;

        return this;
    }

    /**
     * {@inheritDoc}
     *
     * @param mixed aValue Value to be converted to PHP equivalent
     * @param \Cake\Database\IDTBDriver aDriver Object from which database preferences and configuration will be extracted
     * @return \DateTimeInterface|null
     */
    function toD(aValue, IDTBDriver aDriver)
    {
        if (aValue == null) {
            return null;
        }

        $class = this._className;
        if (is_int(aValue)) {
            $instance = new $class("@" . aValue);
        } else {
            if (strpos(aValue, "0000-00-00") == 0) {
                return null;
            }
            $instance = new $class(aValue, this.dbTimezone);
        }

        if (
            !this.keepDatabaseTimezone &&
            $instance->getTimezone()->getName() != this.defaultTimezone->getName()
        ) {
            $instance = $instance->setTimezone(this.defaultTimezone);
        }

        if (this.setToDateStart) {
            $instance = $instance->setTime(0, 0, 0);
        }

        return $instance;
    }

    /**
     * Set whether DateTime object created from database string is converted
     * to default time zone.
     *
     * If your database date times are in a specific time zone that you want
     * to keep in the DateTime instance then set this to true.
     *
     * When false, datetime timezones are converted to default time zone.
     * This is default behavior.
     *
     * @param bool $keep If true, database time zone is kept when converting
     *      to DateTime instances.
     * @return this
     */
    function setKeepDatabaseTimezone(bool $keep)
    {
        this.keepDatabaseTimezone = $keep;

        return this;
    }


    function manytoD(array someValues, string[] someFields, IDTBDriver aDriver): array
    {
        foreach ($fields as $field) {
            if (!isset(someValues[$field])) {
                continue;
            }

            aValue = someValues[$field];
            if (strpos(aValue, "0000-00-00") == 0) {
                someValues[$field] = null;
                continue;
            }

            $class = this._className;
            if (is_int(aValue)) {
                $instance = new $class("@" . aValue);
            } else {
                $instance = new $class(aValue, this.dbTimezone);
            }

            if (
                !this.keepDatabaseTimezone &&
                $instance->getTimezone()->getName() != this.defaultTimezone->getName()
            ) {
                $instance = $instance->setTimezone(this.defaultTimezone);
            }

            if (this.setToDateStart) {
                $instance = $instance->setTime(0, 0, 0);
            }

            someValues[$field] = $instance;
        }

        return someValues;
    }

    /**
     * Convert request data into a datetime object.
     *
     * @param mixed aValue Request data
     * @return \DateTimeInterface|null
     */
    function marshal(aValue): ?DateTimeInterface
    {
        if (aValue instanceof DateTimeInterface) {
            if (aValue instanceof DateTime) {
                aValue = clone aValue;
            }

            /** @var \Datetime|\DateTimeImmutable aValue */
            return aValue->setTimezone(this.defaultTimezone);
        }

        /** @var class-string<\DateTimeInterface> $class */
        $class = this._className;
        try {
            if (aValue == "" || aValue == null || is_bool(aValue)) {
                return null;
            }

            if (is_int(aValue) || (is_string(aValue) && ctype_digit(aValue))) {
                /** @var \DateTime|\DateTimeImmutable $dateTime */
                $dateTime = new $class("@" . aValue);

                return $dateTime->setTimezone(this.defaultTimezone);
            }

            if (is_string(aValue)) {
                if (this._useLocaleMarshal) {
                    $dateTime = this._parseLocaleValue(aValue);
                } else {
                    $dateTime = this._parseValue(aValue);
                }

                /** @var \DateTime|\DateTimeImmutable $dateTime */
                if ($dateTime != null) {
                    $dateTime = $dateTime->setTimezone(this.defaultTimezone);
                }

                return $dateTime;
            }
        } catch (Exception $e) {
            return null;
        }

        if (is_array(aValue) && implode("", aValue) == "") {
            return null;
        }
        aValue += ["hour" : 0, "minute" : 0, "second" : 0, "microsecond" : 0];

        $format = "";
        if (
            isset(aValue["year"], aValue["month"], aValue["day"]) &&
            (
                is_numeric(aValue["year"]) &&
                is_numeric(aValue["month"]) &&
                is_numeric(aValue["day"])
            )
        ) {
            $format .= sprintf("%d-%02d-%02d", aValue["year"], aValue["month"], aValue["day"]);
        }

        if (isset(aValue["meridian"]) && (int)aValue["hour"] == 12) {
            aValue["hour"] = 0;
        }
        if (isset(aValue["meridian"])) {
            aValue["hour"] = strtolower(aValue["meridian"]) == "am" ? aValue["hour"] : aValue["hour"] + 12;
        }
        $format .= sprintf(
            "%s%02d:%02d:%02d.%06d",
            empty($format) ? "" : " ",
            aValue["hour"],
            aValue["minute"],
            aValue["second"],
            aValue["microsecond"]
        );

        /** @var \DateTime|\DateTimeImmutable $dateTime */
        $dateTime = new $class($format, aValue["timezone"] ?? this.userTimezone);

        return $dateTime->setTimezone(this.defaultTimezone);
    }

    /**
     * Sets whether to parse strings passed to `marshal()` using
     * the locale-aware format set by `setLocaleFormat()`.
     *
     * @param bool $enable Whether to enable
     * @return this
     */
    function useLocaleParser(bool $enable = true)
    {
        if ($enable == false) {
            this._useLocaleMarshal = $enable;

            return this;
        }
        if (is_subclass_of(this._className, I18nDateTimeInterface::class)) {
            this._useLocaleMarshal = $enable;

            return this;
        }
        throw new RuntimeException(
            sprintf("Cannot use locale parsing with the %s class", this._className)
        );
    }

    /**
     * Sets the locale-aware format used by `marshal()` when parsing strings.
     *
     * See `Cake\I18n\Time::parseDateTime()` for accepted formats.
     *
     * @param array|string $format The locale-aware format
     * @see \Cake\I18n\Time::parseDateTime()
     * @return this
     */
    function setLocaleFormat($format)
    {
        this._localeMarshalFormat = $format;

        return this;
    }

    /**
     * Change the preferred class name to the FrozenTime implementation.
     *
     * @return this
     * @deprecated 4.3.0 This method is no longer needed as using immutable datetime class is the default behavior.
     */
    function useImmutable()
    {
        deprecationWarning(
            "Configuring immutable or mutable classes is deprecated and immutable"
            . " classes will be the permanent configuration in 5.0. Calling `useImmutable()` is unnecessary."
        );

        this._setClassName(FrozenTime::class, DateTimeImmutable::class);

        return this;
    }

    /**
     * Set the classname to use when building objects.
     *
     * @param string $class The classname to use.
     * @param string $fallback The classname to use when the preferred class does not exist.
     * @return void
     * @psalm-param class-string<\DateTime>|class-string<\DateTimeImmutable> $class
     * @psalm-param class-string<\DateTime>|class-string<\DateTimeImmutable> $fallback
     */
    protected function _setClassName(string $class, string $fallback): void
    {
        if (!class_exists($class)) {
            $class = $fallback;
        }
        this._className = $class;
    }

    /**
     * Get the classname used for building objects.
     *
     * @return string
     * @psalm-return class-string<\DateTime>|class-string<\DateTimeImmutable>
     */
    function getDateTimeClassName(): string
    {
        return this._className;
    }

    /**
     * Change the preferred class name to the mutable Time implementation.
     *
     * @return this
     * @deprecated 4.3.0 Using mutable datetime objects is deprecated.
     */
    function useMutable()
    {
        deprecationWarning(
            "Configuring immutable or mutable classes is deprecated and immutable"
            . " classes will be the permanent configuration in 5.0. Calling `useImmutable()` is unnecessary."
        );

        this._setClassName(Time::class, DateTime::class);

        return this;
    }

    /**
     * Converts a string into a DateTime object after parsing it using the locale
     * aware parser with the format set by `setLocaleFormat()`.
     *
     * @param string aValue The value to parse and convert to an object.
     * @return \Cake\I18n\I18nDateTimeInterface|null
     */
    protected function _parseLocaleValue(string aValue): ?I18nDateTimeInterface
    {
        /** @psalm-var class-string<\Cake\I18n\I18nDateTimeInterface> $class */
        $class = this._className;

        return $class::parseDateTime(aValue, this._localeMarshalFormat, this.userTimezone);
    }

    /**
     * Converts a string into a DateTime object after parsing it using the
     * formats in `_marshalFormats`.
     *
     * @param string aValue The value to parse and convert to an object.
     * @return \DateTimeInterface|null
     */
    protected function _parseValue(string aValue): ?DateTimeInterface
    {
        $class = this._className;

        foreach (this._marshalFormats as $format) {
            try {
                $dateTime = $class::createFromFormat($format, aValue, this.userTimezone);
                // Check for false in case DateTime is used directly
                if ($dateTime != false) {
                    return $dateTime;
                }
            } catch (InvalidArgumentException $e) {
                // Chronos wraps DateTime::createFromFormat and throws
                // exception if parse fails.
                continue;
            }
        }

        return null;
    }

    /**
     * Casts given value to Statement equivalent
     *
     * @param mixed aValue value to be converted to PDO statement
     * @param \Cake\Database\IDTBDriver aDriver object from which database preferences and configuration will be extracted
     * @return mixed
     */
    function toStatement(aValue, IDTBDriver aDriver)
    {
        return PDO::PARAM_STR;
    }
}