module odood.utils.versioned;

private import std.conv: to, ConvOverflowException, ConvException;
private import std.range: empty, zip;
private import std.algorithm.searching: canFind;
private import std.string : isNumeric;
private import std.array: split;
private import std.typecons;
private import std.ascii: isDigit, isAlphaNum;

// Try to convert to int, if possible. on error just return null
private template tryConvertTo(T) {
    Nullable!T tryConvertTo(S)(S s) nothrow {
        try {
            return s.to!T.nullable;
        } catch (Exception e) {
            return Nullable!T.init;
        }
        return Nullable!T.init;
    }
}

// Version parts
enum VersionPart {
    MAJOR,
    MINOR,
    PATCH,
    PRERELEASE,
    BUILD
}


/** Determine next version part to be parsed based on delimiter and current version part being parsed
  *
  * Params:
  *     current = Current version part that is parsed
  *     delimiter = Char that assumed to be delimiter for this version part.
  * Returns:
  *     next version part to be parsed, or null if cannot determine next version part to be parsed
  **/
private nothrow Nullable!VersionPart nextVersionPart(in VersionPart current, in char delimiter) pure @safe {
    final switch(current) {
        case VersionPart.MAJOR:
            switch(delimiter) {
                case '.': return VersionPart.MINOR.nullable;
                case '-': return VersionPart.PRERELEASE.nullable;
                case '+': return VersionPart.BUILD.nullable;
                default: return Nullable!VersionPart.init;
            }
        case VersionPart.MINOR:
            switch(delimiter) {
                case '.': return VersionPart.PATCH.nullable;
                case '-': return VersionPart.PRERELEASE.nullable;
                case '+': return VersionPart.BUILD.nullable;
                default: return Nullable!VersionPart.init;
            }
        case VersionPart.PATCH:
            switch(delimiter) {
                case '-': return VersionPart.PRERELEASE.nullable;
                case '+': return VersionPart.BUILD.nullable;
                default: return Nullable!VersionPart.init;
            }
        case VersionPart.PRERELEASE:
            switch(delimiter) {
                case '+': return VersionPart.BUILD.nullable;
                default: return Nullable!VersionPart.init;
            }
        case VersionPart.BUILD:
            return Nullable!VersionPart.init;
    }
}

/** Check if symbol is delimiter for versione part.
  * This func is used to determine if we reached version part delimiter and we should start parsing next version part
  *
  * Params:
  *     current = Current version parsed.
  *     symbol = current symbol to check if it is delimiter for current version part
  * Returns:
  *     True if sybol if delimiter of current version part
  **/
private nothrow bool isVersionDelimiter(in VersionPart current, in char symbol) pure @safe {
    final switch(current) {
        case VersionPart.MAJOR, VersionPart.MINOR:
            return symbol == '.' || symbol == '-' || symbol == '+';
        case VersionPart.PATCH:
            return symbol == '-' || symbol == '+';
        case VersionPart.PRERELEASE:
            return symbol == '+';
        case VersionPart.BUILD:
            return false;
    }
}

/** Validate version fragment
  **/
private nothrow bool isVersionFragmentValid(in VersionPart part, in string fragment) pure @safe {
    foreach(c; fragment)
    final switch(part) {
        case VersionPart.MAJOR, VersionPart.MINOR, VersionPart.PATCH:
            if (!c.isDigit)
                return false;
            break;
        case VersionPart.PRERELEASE, VersionPart.BUILD:
            if (!c.isAlphaNum && c != '.' && c != '-')
                return false;
            break;
    }
    return true;
}


/** Version struct represents semantic version
  **/
@safe pure struct Version {
    private uint _major=0;
    private uint _minor=0;
    private uint _patch=0;
    private string _prerelease;
    private string _build;
    private bool _isValid=false;

    this(in uint major, in uint minor=0, in uint patch=0) nothrow pure {
        _major = major;
        _minor = minor;
        _patch = patch;
        _isValid = true;
    }

    this(in string v) pure nothrow {
        _isValid = true;  // assume version is valid
        if (v.length == 0) return;

        /* Idea of parsing is simple:
         * start looking for major version part and take all symbols up to
         * delimiter. When delimiter is reached, then save this value
         * as current part, and change the part we are looking for to next one.
         * Each part can have different delimiters. For example, when we are
         * looking for MAJOR, the delimiters are ('.', '-', '+'), but when
         * we are looking for PATCH, the delimiters are ('-', '+'), because
         * we do not expect version parts except prerelease (which separated
         * via '-') and build (which separated via '+').
         */
        uint start = 0;
        if (v[0] == 'v' || v[0] == 'V') {
            // If version starts with 'v' or 'V' prefix, just skip it;
            start = 1;
        }
        VersionPart stage = VersionPart.MAJOR;
        for(uint i=start; i < v.length; i++) {
            if (i < start) continue;  // TODO: maybe remove.
            auto current = v[i];

            // Skip, unless we reach end of input or delimiter
            if (i < v.length - 1 && !isVersionDelimiter(stage, current))
                continue;

            /* Save reference to current fragment
             * If we reached end of input, we take everything from start index to end.
             * Otherwise, v[i] is delimiter, thus we must not include it in fragment
             */
            string fragment = (i == v.length - 1) ?
                v[start .. $] :
                v[start .. i];

            // Check if version fragment is valid
            if (!isVersionFragmentValid(stage, fragment))
                _isValid = false;

            /* Set value for current version part
             */
            final switch(stage) {
                case VersionPart.MAJOR:
                    auto val = fragment.tryConvertTo!uint;
                    if (val.isNull) _isValid = false;
                    else _major = val.get;
                    break;
                case VersionPart.MINOR:
                    auto val = fragment.tryConvertTo!uint;
                    if (val.isNull) _isValid = false;
                    else _minor = val.get;
                    break;
                case VersionPart.PATCH:
                    auto val = fragment.tryConvertTo!uint;
                    if (val.isNull) _isValid = false;
                    else _patch = val.get;
                    break;
                case VersionPart.PRERELEASE:
                    _prerelease = fragment;
                    break;
                case VersionPart.BUILD:
                    // Build is last possible stage, so here we only check for end of line
                    _build = fragment;
                    break;
            }

            /* At this point, we have saved current fragment to correct version part,
             * thus, we can start parsing next version part
             */ 
            auto next_stage = nextVersionPart(stage, current);
            if (!next_stage.isNull) {
                stage = next_stage.get;
                start = i + 1;
            }
        }
    }

    /// Major part of version
    nothrow uint major() const pure { return _major; }

    /// Minor part of version
    nothrow uint minor() const pure { return _minor; }

    /// Patch part of version
    nothrow uint patch() const pure { return _patch; }

    /** Prerelease part of version
      * See: https://semver.org/#spec-item-9
      **/
    nothrow string prerelease() const pure { return _prerelease; }

    /** Build part of version.
      * This part usualy contains metadata for version, and not used to determine priority
      * See: https://semver.org/#spec-item-10
      **/
    nothrow string build() const pure { return _build; }

    /// Is this version valid
    nothrow bool isValid() const pure { return _isValid; }

    // Test valid/invalid versions
    unittest {
        import unit_threaded.assertions;

        Version("1").isValid.should == true;
        Version("1.2").isValid.should == true;
        Version("1.2.3").isValid.should == true;
        Version("1.2.3+test").isValid.should == true;
        Version("1.2.3-alpha").isValid.should == true;
        Version("1.2.3-alpha+test").isValid.should == true;
        Version("1.2.3-alpha.t1+test.t2").isValid.should == true;
        Version("1.2.3-alpha-b1.t1+test-build.t2").isValid.should == true;

        Version("2s").isValid.should == false;
        Version("2.3s").isValid.should == false;
        Version("2.3.4s").isValid.should == false;
        Version("2.3.4-s").isValid.should == true;
        Version("a.b.c").isValid.should == false;
        Version("1.2.3-Ї").isValid.should == false;
        Version("1.2.3-alpha+Ї").isValid.should == false;
        Version("1.2.3-alpha.Й+Ї").isValid.should == false;
    }


    /// Is this version stable
    nothrow bool isStable() const pure { return _prerelease.empty; }

    /// Convert this version to string
    nothrow string toString() const pure {
        string result = _major.to!string ~ "." ~ _minor.to!string ~ "." ~
            _patch.to!string;
        if (_prerelease.length > 0)
            result ~= "-" ~ _prerelease;
        if (_build.length > 0)
            result ~= "+" ~ _build;
        return result;
    }

    ///
    unittest {
        import unit_threaded.assertions;
        Version("1.2.3").major.should == 1;
        Version("1.2.3").minor.should == 2;
        Version("1.2.3").patch.should == 3;
        Version("1.2.3").toString.should == "1.2.3";
        Version("1.2.3").isValid.should == true;
        Version("1.2.3").isStable.should == true;

        Version("v1.2.3").major.should == 1;
        Version("v1.2.3").minor.should == 2;
        Version("v1.2.3").patch.should == 3;
        Version("v1.2.3").toString.should == "1.2.3";
        Version("v1.2.3").isValid.should == true;
        Version("v1.2.3").isStable.should == true;

        Version("1.2").major.should == 1;
        Version("1.2").minor.should == 2;
        Version("1.2").patch.should == 0;
        Version("1.2").toString.should == "1.2.0";
        Version("1.2").isValid.should == true;
        Version("1.2").isStable.should == true;

        Version("1").major.should == 1;
        Version("1").minor.should == 0;
        Version("1").patch.should == 0;
        Version("1").toString.should == "1.0.0";
        Version("1").isValid.should == true;
        Version("1").isStable.should == true;

        Version("1.2.3-alpha").prerelease.should == "alpha";
        Version("1.2.3-alpha").isValid.should == true;
        Version("1.2.3-alpha+build").prerelease.should == "alpha";
        Version("1.2.3-alpha+build").build.should == "build";
        Version("1.2.3-alpha+build").toString.should == "1.2.3-alpha+build";
        Version("1.2.3-alpha+build").isValid.should == true;
        Version("1.2.3-alpha+build").isStable.should == false;

        Version("1.2-alpha+build").major.should == 1;
        Version("1.2-alpha+build").minor.should == 2;
        Version("1.2-alpha+build").patch.should == 0;
        Version("1.2-alpha+build").prerelease.should == "alpha";
        Version("1.2-alpha+build").prerelease.should == "alpha";
        Version("1.2-alpha+build").build.should == "build";
        Version("1.2-alpha+build").toString.should == "1.2.0-alpha+build";
        Version("1.2-alpha+build").isValid.should == true;
        Version("1.2-alpha+build").isStable.should == false;

        Version("1-alpha+build").major.should == 1;
        Version("1-alpha+build").minor.should == 0;
        Version("1-alpha+build").patch.should == 0;
        Version("1-alpha+build").prerelease.should == "alpha";
        Version("1-alpha+build").prerelease.should == "alpha";
        Version("1-alpha+build").build.should == "build";
        Version("1-alpha+build").toString.should == "1.0.0-alpha+build";
        Version("1-alpha+build").isValid.should == true;
        Version("1-alpha+build").isStable.should == false;

        Version("1.2+build").major.should == 1;
        Version("1.2+build").minor.should == 2;
        Version("1.2+build").patch.should == 0;
        Version("1.2+build").prerelease.should == "";
        Version("1.2+build").prerelease.should == "";
        Version("1.2+build").build.should == "build";
        Version("1.2+build").toString.should == "1.2.0+build";
        Version("1.2+build").isValid.should == true;
        Version("1.2+build").isStable.should == true;

        Version("1+build").major.should == 1;
        Version("1+build").minor.should == 0;
        Version("1+build").patch.should == 0;
        Version("1+build").prerelease.should == "";
        Version("1+build").prerelease.should == "";
        Version("1+build").build.should == "build";
        Version("1+build").toString.should == "1.0.0+build";
        Version("1+build").isValid.should == true;
        Version("1+build").isStable.should == true;

        Version("12.34.56").major.should == 12;
        Version("12.34.56").minor.should == 34;
        Version("12.34.56").patch.should == 56;
        Version("12.34.56").isValid.should == true;
        Version("12.34.56-alpha.beta").prerelease.should == "alpha.beta";
        Version("12.34.56-alpha.beta").isValid.should == true;
        Version("12.34.56-alpha.beta").isStable.should == false;
        Version("12.34.56-alpha.beta+build").prerelease.should == "alpha.beta";
        Version("12.34.56-alpha.beta+build").build.should == "build";
        Version("12.34.56-alpha.beta+build").toString.should == "12.34.56-alpha.beta+build";
        Version("12.34.56-alpha.beta+build").isValid.should == true;
        Version("12.34.56-alpha.beta+build").isStable.should == false;

        Version("V12.34.56").major.should == 12;
        Version("V12.34.56").minor.should == 34;
        Version("V12.34.56").patch.should == 56;
        Version("V12.34.56").isValid.should == true;
        Version("V12.34.56-alpha.beta").prerelease.should == "alpha.beta";
        Version("V12.34.56-alpha.beta").isValid.should == true;
        Version("V12.34.56-alpha.beta").isStable.should == false;
        Version("V12.34.56-alpha.beta+build").prerelease.should == "alpha.beta";
        Version("V12.34.56-alpha.beta+build").build.should == "build";
        Version("V12.34.56-alpha.beta+build").toString.should == "12.34.56-alpha.beta+build";
        Version("V12.34.56-alpha.beta+build").isValid.should == true;
        Version("V12.34.56-alpha.beta+build").isStable.should == false;

        Version("12.34.56-alpha").prerelease.should == "alpha";
        Version("12.34.56-alpha-42").prerelease.should == "alpha-42";
        Version("12.34.56-alpha-42").isValid.should == true;
        Version("12.34.56-alpha-42").isStable.should == false;

        Version("12.34.56+build").prerelease.should == "";
        Version("12.34.56+build").build.should == "build";
        Version("12.34.56+build-42").build.should == "build-42";
        Version("12.34.56+build-42").isValid.should == true;
        Version("12.34.56+build-42").isStable.should == true;
    }

    /// Compare current version
    int opCmp(in Version other) const pure nothrow {
        if (this.major != other.major)
            return this.major < other.major ? -1 : 1;
        if (this.minor != other.minor)
            return this.minor < other.minor ? -1 : 1;
        if (this.patch != other.patch)
            return this.patch < other.patch ? -1 : 1;

        // Just copypasteedit from semver lib
        int compareSufix(scope const string[] suffix, const string[] anotherSuffix)
        {
            if (!suffix.empty && anotherSuffix.empty)
                return -1;
            if (suffix.empty && !anotherSuffix.empty)
                return 1;

            foreach (a, b; zip(suffix, anotherSuffix))
            {
                if (a.isNumeric && b.isNumeric)
                {
                    // to convert parts to integers and comare as integers
                    auto ai = a.tryConvertTo!uint,
                         bi = b.tryConvertTo!uint;
                    if (!ai.isNull && !bi.isNull && ai.get != bi.get)
                        return ai.get < bi.get ? -1 : 1;
                }
                if (a != b)
                    return a < b ? -1 : 1;
            }
            if (suffix.length != anotherSuffix.length)
                return suffix.length < anotherSuffix.length ? -1 : 1;
            else
                return 0;
        }

        // Compare prerelease section of version
        auto result = compareSufix(this.prerelease.split("."), other.prerelease.split("."));
        if (result == 0)
            result = compareSufix(this.build.split("."), other.build.split("."));
        return result;
    }

    /// ditto
    int opCmp(in string other) const pure {
        return this.opCmp(Version(other));
    }

    /// Test version comparisons
    unittest {
        import unit_threaded.assertions;
        assert(Version("1.0.0-alpha") < Version("1.0.0-alpha.1"));
        assert(Version("1.0.0-alpha.1") < Version("1.0.0-alpha.beta"));
        assert(Version("1.0.0-alpha.beta") < Version("1.0.0-beta"));
        assert(Version("1.0.0-beta") < Version("1.0.0-beta.2"));
        assert(Version("1.0.0-beta.2") < Version("1.0.0-beta.11"));
        assert(Version("1.0.0-beta.11") < Version("1.0.0-rc.1"));
        assert(Version("1.0.0-rc.1") < Version("1.0.0"));
        assert(Version("1.0.0-rc.1") > Version("1.0.0-rc.1+build.5"));
        assert(Version("1.0.0-rc.1+build.5") == Version("1.0.0-rc.1+build.5"));
        assert(Version("1.0.0-rc.1+build.5") != Version("1.0.0-rc.1+build.6"));
        assert(Version("1.0.0-rc.2+build.5") != Version("1.0.0-rc.1+build.5"));
    }

    /// Test comparisons with strings
    unittest {
        import unit_threaded.assertions;
        assert(Version("1.0.0-alpha") < "1.0.0-alpha.1");
        assert(Version("1.0.0-alpha.1") < "1.0.0-alpha.beta");
        assert(Version("1.0.0-alpha.beta") < "1.0.0-beta");
        assert(Version("1.0.0-beta") < "1.0.0-beta.2");
        assert(Version("1.0.0-beta.2") < "1.0.0-beta.11");
        assert(Version("1.0.0-beta.11") < "1.0.0-rc.1");
        assert(Version("1.0.0-rc.1") < "1.0.0");
        assert(Version("1.0.0-rc.1") > "1.0.0-rc.1+build.5");
        assert(Version("1.0.0-rc.1+build.5") == "1.0.0-rc.1+build.5");
        assert(Version("1.0.0-rc.1+build.5") != "1.0.0-rc.1+build.6");
        assert(Version("1.0.0-rc.2+build.5") != "1.0.0-rc.1+build.5");
    }

    /// Check if other version is equal to current version
    bool opEquals(in Version other) const nothrow pure {
        return this.major == other.major &&
            this.minor == other.minor &&
            this.patch == other.patch &&
            this.prerelease == other.prerelease &&
            this.build == other.build;
    }

    /// ditto
    bool opEquals(in string other) const pure {
        return this.opEquals(Version(other));
    }

    /// Test equality checks
    unittest {
        import unit_threaded.assertions;
        Version("1.2.3").should == Version(1, 2, 3);
        Version("1.2").should == Version(1, 2);
        Version("1.0.3").should == Version(1, 0, 3);
        // TODO: more tests needed
    }

    /// Test equality checks with strings
    unittest {
        import unit_threaded.assertions;
        assert(Version("1.2.3") == "1.2.3");
        assert(Version("1.2") == "1.2");
        assert(Version("1.0.3") == "1.0.3");
        // TODO: more tests needed
    }

    /// Return new version with increased major part
    auto incMajor() const pure {
        return Version(major +1 , 0, 0);
    }

    /// Test increase of major version
    unittest {
        import unit_threaded.assertions;
        Version("1.2.3").incMajor.should == Version("2.0.0");
    }

    /// Return new version with increased minor part
    auto incMinor() const pure {
        return Version(major, minor + 1, 0);
    }

    /// Test increase of minor version
    unittest {
        import unit_threaded.assertions;
        Version("1.2.3").incMinor.should == Version("1.3.0");
    }

    /// Return new version with increased patch part
    auto incPatch() const pure {
        return Version(major, minor, patch + 1);
    }

    /// Test increase of minor version
    unittest {
        import unit_threaded.assertions;
        Version("1.2.3").incPatch.should == Version("1.2.4");
    }

    /// Determine if version differs on major, minor or patch level
    VersionPart differAt(in Version other) const pure
    in (this != other && this.isValid && other.isValid) {
        if (this.major != other.major) return VersionPart.MAJOR;
        if (this.minor != other.minor) return VersionPart.MINOR;
        if (this.patch != other.patch) return VersionPart.PATCH;
        if (this.prerelease != other.prerelease) return VersionPart.PRERELEASE;
        if (this.build != other.build) return VersionPart.BUILD;
        assert(0, "differAt cannot compare equal versions.");
    }

    /// Test differAt
    unittest {
        import unit_threaded.assertions;
        Version("1.2.3").differAt(Version(2,3,4)).should == VersionPart.MAJOR;
        Version("1.2.3").differAt(Version(2,2,3)).should == VersionPart.MAJOR;

        Version("1.2.3").differAt(Version(1,3,4)).should == VersionPart.MINOR;
        Version("1.2.3").differAt(Version(1,3,3)).should == VersionPart.MINOR;

        Version("1.2.3").differAt(Version(1,2,4)).should == VersionPart.PATCH;
    }
}

