package ElasticSearch;

use strict;
use warnings FATAL => 'all';

use constant {
    ONE_REQ     => 1,
    ONE_OPT     => 2,
    MULTI_ALL   => 3,
    MULTI_BLANK => 4,
};

use constant {
    CMD_NONE          => [],
    CMD_INDEX_TYPE_ID => [ index => ONE_REQ, type => ONE_REQ, id => ONE_REQ ],
    CMD_INDEX_TYPE_id => [ index => ONE_REQ, type => ONE_REQ, id => ONE_OPT ],
    CMD_index      => [ index => MULTI_BLANK ],
    CMD_INDEX      => [ index => ONE_REQ ],
    CMD_INDEX_TYPE => [ index => ONE_REQ, type => ONE_REQ ],
    CMD_INDEX_type => [ index => ONE_REQ, type => MULTI_BLANK ],
    CMD_index_TYPE => [ index => MULTI_ALL, type => ONE_REQ ],
    CMD_index_type => [ index => MULTI_ALL, type => MULTI_BLANK ],
    CMD_RIVER      => [ river => ONE_REQ ],
    CMD_nodes      => [ node  => MULTI_BLANK ],
    CMD_NAME       => [ name  => ONE_REQ ],
    CMD_INDEX_PERC => [ index => ONE_REQ, percolator => ONE_REQ ],
};

our %QS_Format = (
    boolean  => '1 | 0',
    duration => "'5m' | '10s'",
    optional => "'scalar value'",
    flatten  => "'scalar' or ['scalar_1', 'scalar_n']",
    'int'    => "integer",
    string   => '"string"',
    float    => 'float',
    enum     => '"predefined_value"',
);

our %QS_Formatter = (
    boolean => sub {
        my $key = shift;
        my $val = $_[0] ? $_[1] : $_[2];
        return unless defined $val;
        return ref $val ? $val : [ $key, $val ? 'true' : 'false' ];
    },
    duration => sub {
        my ( $k, $t ) = @_;
        return unless defined $t;
        return [ $k, $t ] if $t =~ /^\d+([smh]|ms)$/i;
        die "$k '$t' is not in the form $QS_Format{duration}\n";
    },
    flatten => sub {
        my $key = shift;
        my $array = shift or return;
        return [ $key, ref $array ? join( ',', @$array ) : $array ];
    },
    'int' => sub {
        my $key = shift;
        my $int = shift;
        return unless defined $int;
        eval { $int += 0; 1 } or die "'$key' is not an integer";
        return [ $key, $int ];
    },
    'float' => sub {
        my $key   = shift;
        my $float = shift;
        return unless defined $float;
        $key = shift if @_;
        eval { $float += 0; 1 } or die "'$key' is not a float";
        return [ $key, $float ];
    },
    'string' => sub {
        my $key    = shift;
        my $string = shift;
        return unless defined $string;
        return [ $key, $string ];
    },
    'enum' => sub {
        my $key = shift;
        my $val = shift;
        return unless defined $val;
        my $vals = $_[0];
        for (@$vals) {
            return [ $key, $val ] if $val eq $_;
        }
        die "Unrecognised value '$val'. Allowed values: "
            . join( ', ', @$vals );
    },

);

##################################
## DOCUMENT MANAGEMENT
##################################

#===================================
sub get {
#===================================
    shift()->_do_action(
        'get',
        {   cmd => CMD_INDEX_TYPE_ID,
            qs  => {
                fields         => ['flatten'],
                ignore_missing => [ 'boolean', 1 ],
                refresh        => [ 'boolean', 1 ],
                routing        => ['string'],
            },
        },
        @_
    );
}

my %Index_Defn = (
    cmd => CMD_INDEX_TYPE_id,
    qs  => {
        create => [ 'boolean', [ op_type => 'create' ] ],
        refresh   => [ 'boolean', 1 ],
        timeout   => ['duration'],
        routing   => [ 'string', ],
        parent    => [ 'string', ],
        percolate => [ 'string', ],
        version   => [ 'string', ],
    },
    data => 'data',
);

#===================================
sub index {
#===================================
    my ( $self, $params ) = parse_params(@_);

    $self->_index( 'index', \%Index_Defn, $params );
}

#===================================
sub set {
#===================================
    my ( $self, $params ) = parse_params(@_);

    $self->_index( 'set', \%Index_Defn, $params );
}

#===================================
sub create {
#===================================
    my ( $self, $params ) = parse_params(@_);

    $self->_index(
        'create',
        {   cmd     => CMD_INDEX_TYPE_id,
            data    => 'data',
            postfix => '_create',
            qs      => {
                refresh   => [ 'boolean', 1 ],
                timeout   => ['duration'],
                routing   => ['string'],
                parent    => ['string'],
                percolate => ['string'],
            },
        },
        $params
    );
}

#===================================
sub _index {
#===================================
    my $self = shift;
    $_[1]->{method} = $_[2]->{id} ? 'PUT' : 'POST';
    $self->_do_action(@_);
}

#===================================
sub delete {
#===================================
    shift()->_do_action(
        'delete',
        {   method => 'DELETE',
            cmd    => CMD_INDEX_TYPE_ID,
            qs     => {
                consistency => [ 'enum', [ 'one', 'quorom', 'all' ] ],
                ignore_missing => [ 'boolean', 1 ],
                refresh        => [ 'boolean', 1 ],
                routing        => ['string'],
                version        => ['int'],
                replication => [ 'enum', [ 'async', 'sync' ] ],
            }
        },
        @_
    );
}

#===================================
sub analyze {
#===================================
    shift()->_do_action(
        'analyze',
        {   method  => 'GET',
            cmd     => CMD_INDEX,
            postfix => '_analyze',
            qs      => {
                text     => ['string'],
                analyzer => ['string'],
                format   => [ 'enum', [ 'detailed', 'text' ] ],
                prefer_local => [ 'boolean',, 1 ],
            }
        },
        @_
    );
}

##################################
## BULK INTERFACE
##################################

my %Bulk_Actions = (
    'delete' => {
        index   => ONE_REQ,
        type    => ONE_REQ,
        id      => ONE_REQ,
        parent  => ONE_OPT,
        routing => ONE_OPT,
        version => ONE_OPT,
    },
    'index' => {
        index     => ONE_REQ,
        type      => ONE_REQ,
        id        => ONE_OPT,
        data      => ONE_REQ,
        routing   => ONE_OPT,
        parent    => ONE_OPT,
        percolate => ONE_OPT,
        version   => ONE_OPT,
    },
);
$Bulk_Actions{create} = $Bulk_Actions{index};

my %Bulk_QS = (
    consistency => [ 'enum', [ 'one', 'quorom', 'all' ] ],
    refresh => [ 'boolean', 1 ],
);

#===================================
sub bulk {
#===================================
    my $self = shift;
    my ( $actions, $qs );
    if ( ref $_[0] eq 'ARRAY' ) {
        $actions = shift;
        my $params = ref $_[0] eq 'HASH' ? shift : {@_};
        $qs = $self->_build_qs( $params, \%Bulk_QS );
    }
    else {
        $actions = [@_];
    }

    return { actions => [], results => [] } unless @$actions;

    my $json      = $self->transport->JSON;
    my $indenting = $json->get_indent;
    $json->indent(0);

    my $json_docs = eval { $self->_build_bulk_query($actions) };
    my $error = $@;
    $json->indent($indenting);
    die $error unless $json_docs;

    my $results = $self->request( {
            method => 'POST',
            cmd    => '/_bulk',
            qs     => $qs,
            data   => $json_docs
        }
    );
    my $items = $results->{items}
        || $self->throw( 'Request', 'Malformed response to bulk query',
        $results );

    my ( @errors, %matches );

    for ( my $i = 0; $i < @$actions; $i++ ) {
        my ( $action, $item ) = ( %{ $items->[$i] } );
        if ( my $match = $item->{matches} ) {
            push @{ $matches{$_} }, $item for @$match;
        }
        my $error = $items->[$i]{$action}{error} or next;
        push @errors, { action => $actions->[$i], error => $error };
    }

    return {
        actions => $actions,
        results => $items,
        matches => \%matches,
        took    => $results->{took},
        ( @errors ? ( errors => \@errors ) : () )
    };
}

#===================================
sub bulk_index  { shift->_bulk_action( 'index',  @_ ) }
sub bulk_create { shift->_bulk_action( 'create', @_ ) }
sub bulk_delete { shift->_bulk_action( 'delete', @_ ) }
#===================================

#===================================
sub _bulk_action {
#===================================
    my $self    = shift;
    my $action  = shift;
    my $docs    = ref $_[0] eq 'ARRAY' ? shift : [@_];
    my @actions = map {
        { $action => $_ }
    } @$docs;
    return $self->bulk( \@actions, @_ );
}

#===================================
sub _build_bulk_query {
#===================================
    my $self    = shift;
    my $actions = shift;
    my $json    = $self->transport->JSON;

    my $json_docs = '';
    for my $data (@$actions) {

        $self->throw( "Param", 'bulk() expects an array of HASH refs', $data )
            unless ref $data eq 'HASH';

        my ( $action, $params ) = %$data;

        my $defn = $Bulk_Actions{$action}
            || $self->throw( "Param", "Unknown bulk action '$action'" );

        my %metadata;
        $params = {%$params};
        delete @{$params}{qw(_score sort)};
        $params->{data} ||= delete $params->{_source}
            if $params->{_source};

        for my $key ( keys %$defn ) {
            my $val = delete $params->{$key} || delete $params->{"_$key"};
            unless ( defined $val ) {
                next if $defn->{$key} == ONE_OPT;
                $self->throw(
                    'Param',
                    "Missing required param '$key' for bulk action '$action'",
                    $data
                );
            }
            $metadata{"_$key"} = $val;
        }
        if ( exists $metadata{_percolate} ) {
            $metadata{percolate} = delete $metadata{_percolate};
        }
        $self->throw(
            'Param',
            "Unknown params for bulk action '$action': "
                . join( ', ', keys %$params ),
            $data
        ) if keys %$params;

        my $data = delete $metadata{_data};
        my $request = $json->encode( { $action => \%metadata } ) . "\n";
        $request .= $json->encode($data) . "\n"
            if $data;
        $json_docs .= $request;
    }
    return \$json_docs;
}

##################################
## QUERIES
##################################

my %Search_Data = (
    explain       => ['explain'],
    facets        => ['facets'],
    fields        => ['fields'],
    filter        => ['filter'],
    from          => ['from'],
    highlight     => ['highlight'],
    indices_boost => ['indices_boost'],
    script_fields => ['script_fields'],
    size          => ['size'],
    'sort'        => ['sort'],
);

my %Search_Defn = (
    cmd     => CMD_index_type,
    postfix => '_search',
    qs      => {
        search_type => [
            'enum',
            [   qw( dfs_query_then_fetch    dfs_query_and_fetch
                    query_then_fetch         query_and_fetch
                    count                   scan)
            ]
        ],
        routing => [ 'flatten', ],
        scroll  => ['duration'],
        timeout => ['duration'],
        version => [ 'boolean', 1 ],
    },
    data => { %Search_Data, query => ['query'] }
);

my %Query_Defn = (
    bool               => ['bool'],
    constant_score     => ['constant_score'],
    custom_score       => ['custom_score'],
    dis_max            => ['dis_max'],
    field              => ['field'],
    field_masking_span => ['field_masking_span'],
    filtered           => ['filtered'],
    flt                => [ 'flt', 'fuzzy_like_this' ],
    flt_field          => [ 'flt_field', 'fuzzy_like_this_field' ],
    fuzzy              => ['fuzzy'],
    match_all          => ['match_all'],
    min_score          => ['min_score'],
    mlt                => [ 'mlt', 'more_like_this' ],
    mlt_field          => [ 'mlt_field', 'more_like_this_field' ],
    prefix             => ['prefix'],
    query_string       => ['query_string'],
    range              => ['range'],
    span_term          => ['span_term'],
    span_first         => ['span_first'],
    span_near          => ['span_near'],
    span_not           => ['span_not'],
    span_or            => ['span_or'],
    term               => ['term'],
    terms              => [ 'terms', 'in' ],
    wildcard           => ['wildcard'],
);

#===================================
sub search { shift()->_do_action( 'search', \%Search_Defn, @_ ) }
#===================================

#===================================
sub scroll {
#===================================
    shift()->_do_action(
        'scroll',
        {   cmd    => [],
            prefix => '_search/scroll',
            qs     => { scroll_id => ['string'] }
        },
        @_
    );
}

#===================================
sub delete_by_query {
#===================================
    shift()->_do_action(
        'delete_by_query',
        {   %Search_Defn,
            method  => 'DELETE',
            postfix => '_query',
            qs      => {
                consistency => [ 'enum', [ 'one', 'quorom', 'all' ] ],
                replication => [ 'enum', [ 'async', 'sync' ] ],
                routing => ['flatten'],
            },
            data => \%Query_Defn,
        },
        @_
    );
}

#===================================
sub count {
#===================================
    shift()->_do_action(
        'count',
        {   %Search_Defn,
            postfix => '_count',
            data    => \%Query_Defn,
            qs      => { routing => ['flatten'] },
        },
        @_
    );
}

#===================================
sub mlt {
#===================================
    shift()->_do_action(
        'mlt',
        {   cmd    => CMD_INDEX_TYPE_ID,
            method => 'GET',
            qs     => {
                %{ $Search_Defn{qs} },
                mlt_fields         => ['flatten'],
                pct_terms_to_match => [ 'float', 'percent_terms_to_match' ],
                min_term_freq      => ['int'],
                max_query_terms    => ['int'],
                stop_words         => ['flatten'],
                min_doc_freq       => ['int'],
                max_doc_freq       => ['int'],
                min_word_len       => ['int'],
                max_word_len       => ['int'],
                boost_terms        => ['float'],
            },
            postfix => '_mlt',
            data    => \%Search_Data,
        },
        @_
    );
}

##################################
## PERCOLATOR
##################################
#===================================
sub create_percolator {
#===================================
    shift()->_do_action(
        'create_percolator',
        {   cmd    => CMD_INDEX_PERC,
            prefix => '_percolator',
            method => 'PUT',
            data   => { query => 'query', data => ['data'] },
            fixup  => sub {
                my $args = shift;
                die 'The "data" param cannot include a "query" key'
                    if $args->{data}{data}{query};
                $args->{data} = {
                    query => $args->{data}{query},
                    %{ $args->{data}{data} }
                };
                }
        },
        @_
    );

}

#===================================
sub delete_percolator {
#===================================
    shift()->_do_action(
        'delete_percolator',
        {   cmd    => CMD_INDEX_PERC,
            prefix => '_percolator',
            method => 'DELETE',
            qs     => {
                ignore_missing => [ 'boolean', 1 ],

            }
        },
        @_
    );
}

#===================================
sub get_percolator {
#===================================
    my $result = shift()->_do_action(
        'get_percolator',
        {   cmd    => CMD_INDEX_PERC,
            prefix => '_percolator',
            method => 'GET',
            qs     => { ignore_missing => [ 'boolean', 1 ], }
        },
        @_
    );
    return {
        index      => $result->{_type},
        percolator => $result->{_id},
        query      => delete $result->{_source}{query},
        data       => $result->{_source},
    };
}

#===================================
sub percolate {
#===================================
    shift()->_do_action(
        'percolate',
        {   cmd     => CMD_INDEX_TYPE,
            postfix => '_percolate',
            method  => 'GET',
            qs      => { prefer_local => [ 'boolean', undef, 0 ] },
            data    => { doc => 'doc', query => ['query'] },
        },
        @_
    );
}

##################################
## INDEX ADMIN
##################################

#===================================
sub index_status {
#===================================
    shift()->_do_action(
        'index_status',
        {   cmd     => CMD_index,
            postfix => '_status'
        },
        @_
    );
}

#===================================
sub create_index {
#===================================
    shift()->_do_action(
        'create_index',
        {   method  => 'PUT',
            cmd     => CMD_INDEX,
            postfix => '',
            data    => {
                settings => [ 'settings', 'defn' ],
                mappings => ['mappings'],
            },
        },
        @_
    );
}

#===================================
sub delete_index {
#===================================
    shift()->_do_action(
        'delete_index',
        {   method  => 'DELETE',
            cmd     => CMD_INDEX,
            qs      => { ignore_missing => [ 'boolean', 1 ], },
            postfix => ''
        },
        @_
    );
}

#===================================
sub open_index {
#===================================
    shift()->_do_action(
        'open_index',
        {   method  => 'POST',
            cmd     => CMD_INDEX,
            postfix => '_open'
        },
        @_
    );
}

#===================================
sub close_index {
#===================================
    shift()->_do_action(
        'close_index',
        {   method  => 'POST',
            cmd     => CMD_INDEX,
            postfix => '_close'
        },
        @_
    );
}

#===================================
sub aliases {
#===================================
    my ( $self, $params ) = parse_params(@_);
    my $actions = $params->{actions};
    if ( defined $actions && ref $actions ne 'ARRAY' ) {
        $params->{actions} = [$actions];
    }

    $self->_do_action(
        'aliases',
        {   prefix => '_aliases',
            method => 'POST',
            cmd    => [],
            data   => { actions => 'actions' },
        },
        $params
    );
}

#===================================
sub get_aliases {
#===================================
    my ( $self, $params ) = parse_params(@_);

    my $results = $self->index_status($params);
    my $indices = $results->{indices};
    my %aliases = ( indices => {}, aliases => {} );
    foreach my $index ( keys %$indices ) {
        my $aliases = $indices->{$index}{aliases};
        $aliases{indices}{$index} = $aliases;
        for (@$aliases) {
            push @{ $aliases{aliases}{$_} }, $index;
        }

    }
    return \%aliases;
}

#===================================
sub create_index_template {
#===================================
    shift()->_do_action(
        'create_index_template',
        {   method => 'PUT',
            cmd    => CMD_NAME,
            prefix => '_template',
            data   => {
                template => 'template',
                settings => ['settings'],
                mappings => ['mappings']
            },
        },
        @_
    );
}

#===================================
sub delete_index_template {
#===================================
    shift()->_do_action(
        'delete_index_template',
        {   method => 'DELETE',
            cmd    => CMD_NAME,
            prefix => '_template',
            qs     => { ignore_missing => [ 'boolean', 1 ] },
        },
        @_
    );
}

#===================================
sub index_template {
#===================================
    shift()->_do_action(
        'index_template',
        {   method => 'GET',
            cmd    => CMD_NAME,
            prefix => '_template',
        },
        @_
    );
}

#===================================
sub flush_index {
#===================================
    shift()->_do_action(
        'flush_index',
        {   method  => 'POST',
            cmd     => CMD_index,
            postfix => '_flush',
            qs      => {
                refresh => [ 'boolean', 1, 0 ],
                full    => [ 'boolean', 1, 0 ]
            },
        },
        @_
    );
}

#===================================
sub refresh_index {
#===================================
    shift()->_do_action(
        'refresh_index',
        {   method  => 'POST',
            cmd     => CMD_index,
            postfix => '_refresh'
        },
        @_
    );
}
#===================================
sub optimize_index {
#===================================
    shift()->_do_action(
        'optimize_index',
        {   method  => 'POST',
            cmd     => CMD_index,
            postfix => '_optimize',
            qs      => {
                only_deletes =>
                    [ 'boolean', [ only_expunge_deletes => 'true' ] ],
                max_num_segments => ['int'],
                refresh          => [ 'boolean', undef, 0 ],
                flush            => [ 'boolean', undef, 0 ],
                wait_for_merge   => [ 'boolean', undef, 0 ],
            },
        },
        @_
    );
}

#===================================
sub snapshot_index {
#===================================
    shift()->_do_action(
        'snapshot_index',
        {   method  => 'POST',
            cmd     => CMD_index,
            postfix => '_gateway/snapshot'
        },
        @_
    );
}

#===================================
sub gateway_snapshot {
#===================================
    shift()->_do_action(
        'gateway_snapshot',
        {   method  => 'POST',
            cmd     => CMD_index,
            postfix => '_gateway/snapshot'
        },
        @_
    );
}

#===================================
sub put_mapping {
#===================================
    my ( $self, $params ) = parse_params(@_);
    $self->_do_action(
        'put_mapping',
        {   method  => 'PUT',
            cmd     => CMD_index_TYPE,
            postfix => '_mapping',
            qs      => { ignore_conflicts => [ 'boolean', 1 ] },
            data    => {
                dynamic    => ['dynamic'],
                properties => 'properties',
                _all       => ['_all'],
                _analyzer  => ['_analyzer'],
                _boost     => ['_boost'],
                _id        => ['_id'],
                _index     => ['_index'],
                _meta      => ['_meta'],
                _parent    => ['_parent'],
                _routing   => ['_routing'],
                _source    => ['_source'],
            },
            fixup => sub {
                my $args = shift;
                $args->{data} = { $params->{type} => $args->{data} };
                }

        },
        $params
    );

}

#===================================
sub delete_mapping {
#===================================
    my ( $self, $params ) = parse_params(@_);

    $self->_do_action(
        'delete_mapping',
        {   method => 'DELETE',
            cmd    => CMD_index_TYPE,
            qs     => { ignore_missing => [ 'boolean', 1 ], }
        },
        $params
    );
}

#===================================
sub mapping {
#===================================
    my ( $self, $params ) = parse_params(@_);

    $self->_do_action(
        'mapping',
        {   method  => 'GET',
            cmd     => CMD_index_type,
            postfix => '_mapping',
        },
        $params
    );
}

#===================================
sub clear_cache {
#===================================
    shift()->_do_action(
        'clear_cache',
        {   method  => 'POST',
            cmd     => CMD_index,
            postfix => '_cache/clear',
            qs      => {
                id         => [ 'boolean', 1 ],
                field      => [ 'boolean', 1 ],
                field_data => [ 'boolean', 1 ],
                bloom      => [ 'boolean', 1 ],
            }
        },
        @_
    );
}

#===================================
sub update_index_settings {
#===================================
    my ( $self, $params ) = parse_params(@_);

    $self->_do_action(
        'update_settings',
        {   method  => 'PUT',
            cmd     => CMD_index,
            postfix => '_settings',
            data    => { index => 'settings' }
        },
        $params
    );
}

##################################
## RIVER MANAGEMENT
##################################

#===================================
sub create_river {
#===================================
    my ( $self, $params ) = parse_params(@_);
    my $type = $params->{type}
        or $self->throw( 'Param', 'No river type specified', $params );
    my $data = { type => 'type', index => ['index'], $type => [$type] };
    $self->_do_action(
        'create_river',
        {   method  => 'PUT',
            prefix  => '_river',
            cmd     => CMD_RIVER,
            postfix => '_meta',
            data    => $data
        },
        $params
    );
}

#===================================
sub get_river {
#===================================
    my ( $self, $params ) = parse_params(@_);
    $self->_do_action(
        'get_river',
        {   method  => 'GET',
            prefix  => '_river',
            cmd     => CMD_RIVER,
            postfix => '_meta',
            qs      => { ignore_missing => [ 'boolean', 1 ] }
        },
        $params
    );
}

#===================================
sub delete_river {
#===================================
    my ( $self, $params ) = parse_params(@_);
    $self->_do_action(
        'delete_river',
        {   method => 'DELETE',
            prefix => '_river',
            cmd    => CMD_RIVER,
        },
        $params
    );
}

#===================================
sub river_status {
#===================================
    my ( $self, $params ) = parse_params(@_);
    $self->_do_action(
        'river_status',
        {   method  => 'GET',
            prefix  => '_river',
            cmd     => CMD_RIVER,
            postfix => '_status',
            qs      => { ignore_missing => [ 'boolean', 1 ] }
        },
        $params
    );
}

##################################
## CLUSTER MANAGEMENT
##################################

#===================================
sub cluster_state {
#===================================
    shift()->_do_action(
        'cluster_state',
        {   prefix => '_cluster/state',
            qs     => {
                filter_blocks        => [ 'boolean', 1 ],
                filter_nodes         => [ 'boolean', 1 ],
                filter_metadata      => [ 'boolean', 1 ],
                filter_routing_table => [ 'boolean', 1 ],
                filter_indices       => ['flatten'],
                }

        },
        @_
    );
}

#===================================
sub current_server_version {
#===================================
    shift()
        ->_do_action( 'current_server_version',
        { cmd => CMD_NONE, prefix => '' } )->{version};
}

#===================================
sub nodes {
#===================================
    shift()->_do_action(
        'nodes',
        {   prefix => '_cluster/nodes',
            cmd    => CMD_nodes,
            qs     => { settings => [ 'boolean', 1 ] }
        },
        @_
    );
}

#===================================
sub nodes_stats {
#===================================
    shift()->_do_action(
        'nodes',
        {   prefix  => '_cluster/nodes',
            postfix => 'stats',
            cmd     => CMD_nodes,
        },
        @_
    );
}

#===================================
sub shutdown {
#===================================
    shift()->_do_action(
        'shutdown',
        {   method  => 'POST',
            prefix  => '_cluster/nodes',
            cmd     => CMD_nodes,
            postfix => '_shutdown',
            qs      => { delay => ['duration'] }
        },
        @_
    );
}

#===================================
sub restart {
#===================================
    shift()->_do_action(
        'shutdown',
        {   method  => 'POST',
            prefix  => '_cluster/nodes',
            cmd     => CMD_nodes,
            postfix => '_restart',
            qs      => { delay => ['duration'] }
        },
        @_
    );
}

#===================================
sub cluster_health {
#===================================
    shift()->_do_action(
        'cluster_health',
        {   prefix => '_cluster/health',
            cmd    => CMD_index,
            qs     => {
                level           => [ 'enum', [qw(cluster indices shards)] ],
                wait_for_status => [ 'enum', [qw(green yellow red)] ],
                wait_for_relocating_shards => ['int'],
                wait_for_nodes             => ['string'],
                timeout                    => ['duration']
            }
        },
        @_
    );
}

##################################
## FLAGS
##################################

#===================================
sub camel_case {
#===================================
    my $self = shift;
    if (@_) {
        if ( shift() ) {
            $self->{_base_qs}{case} = 'camelCase';
        }
        else {
            delete $self->{_base_qs}{case};
        }
    }
    return $self->{_base_qs}{case} ? 1 : 0;
}

#===================================
sub error_trace {
#===================================
    my $self = shift;
    if (@_) {
        if ( shift() ) {
            $self->{_base_qs}{error_trace} = 'true';
        }
        else {
            delete $self->{_base_qs}{error_trace};
        }
    }
    return $self->{_base_qs}{error_trace} ? 1 : 0;
}

##################################
## INTERNAL
##################################

#===================================
sub _do_action {
#===================================
    my $self            = shift;
    my $action          = shift || '';
    my $defn            = shift || {};
    my $original_params = $self->parse_params(@_);

    my $error;

    my $params = {%$original_params};
    my %args = ( method => $defn->{method} || 'GET' );

    eval {
        $args{cmd}
            = $self->_build_cmd( $params, @{$defn}{qw(prefix cmd postfix)} );
        $args{qs} = $self->_build_qs( $params, $defn->{qs} );
        $args{data} = $self->_build_data( $params, $defn->{data} );
        if ( my $fixup = $defn->{fixup} ) {
            $fixup->( \%args );
        }
        die "Unknown parameters: " . join( ', ', keys %$params ) . "\n"
            if keys %$params;
        1;
    } or $error = $@ || 'Unknown error';

    $self->throw(
        'Param',
        $error . $self->_usage( $action, $defn ),
        { params => $original_params }
    ) if $error;

    return $self->request( \%args );
}

#===================================
sub _usage {
#===================================
    my $self   = shift;
    my $action = shift;
    my $defn   = shift;

    my $usage = "Usage for '$action()':\n";
    my @cmd = @{ $defn->{cmd} || [] };
    while ( my $key = shift @cmd ) {
        my $type = shift @cmd;
        my $arg_format
            = $type == ONE_REQ ? "\$$key"
            : $type == ONE_OPT ? "\$$key"
            :                    "\$$key | [\$${key}_1,\$${key}_n]";

        my $required = $type == ONE_REQ ? 'required' : 'optional';
        $usage .= sprintf( "  - %-26s =>  %-45s # %s\n",
            $key, $arg_format, $required );
    }
    if ( my $qs = $defn->{qs} ) {
        for ( sort keys %$qs ) {
            my $arg_format = $QS_Format{ $qs->{$_}[0] };
            $usage .= sprintf( "  - %-26s =>  %-45s # optional\n", $_,
                $arg_format );
        }
    }

    if ( my $data = $defn->{data} ) {
        $data = { data => $data } unless ref $data eq 'HASH';
        my @keys = sort { $a->[0] cmp $b->[0] }
            map { ref $_ ? [ $_->[0], 'optional' ] : [ $_, 'required' ] }
            values %$data;

        for (@keys) {
            $usage .= sprintf(
                "  - %-26s =>  %-45s # %s\n",
                $_->[0], '{' . $_->[0] . '}',
                $_->[1]
            );
        }
    }
    return $usage;
}

#===================================
sub _build_qs {
#===================================
    my $self   = shift;
    my $params = shift;
    my $defn   = shift or return;
    my %qs     = %{ $self->{_base_qs} };
    foreach my $key ( keys %$defn ) {
        my ( $format_name, @args ) = @{ $defn->{$key} || [] };
        $format_name ||= '';

        next unless exists $params->{$key};

        my $formatter = $QS_Formatter{$format_name}
            or die "Unknown QS formatter '$format_name'";

        my $val = $formatter->( $key, delete $params->{$key}, @args )
            or next;
        $qs{ $val->[0] } = $val->[1];
    }
    return \%qs;
}

#===================================
sub _build_data {
#===================================
    my $self   = shift;
    my $params = shift;
    my $defn   = shift or return;

    my $top_level;
    if ( ref $defn ne 'HASH' ) {
        $top_level = 1;
        $defn = { data => $defn };
    }

    my %data;
KEY: while ( my ( $key, $source ) = each %$defn ) {
        if ( ref $source eq 'ARRAY' ) {
            foreach (@$source) {
                my $val = delete $params->{$_};
                next unless defined $val;
                $data{$key} = $val;
                next KEY;
            }
        }
        else {
            $data{$key} = delete $params->{$source}
                or die "Missing required param '$source'\n";
        }
    }
    if ($top_level) {
        die "Param '$defn' is not a HASH ref"
            unless ref $data{data} eq 'HASH';
        return $data{data};
    }
    return \%data;
}

#===================================
sub _build_cmd {
#===================================
    my $self   = shift;
    my $params = shift;
    my ( $prefix, $defn, $postfix ) = @_;

    my @defn = ( @{ $defn || [] } );
    my @cmd;
    while (@defn) {
        my $key  = shift @defn;
        my $type = shift @defn;

        my $val = delete $params->{$key};
        if ( defined $val ) {
            if ( ref $val eq 'ARRAY' ) {
                die "'$key' must be a single value\n"
                    if $type == ONE_REQ || $type == ONE_OPT;
                $val = join ',', @$val;
            }
        }
        else {
            next if $type == ONE_OPT || $type == MULTI_BLANK;
            die "Param '$key' is required\n"
                if $type == ONE_REQ;
            $val = '_all';
        }
        push @cmd, $val;
    }

    return join '/', '', grep {defined} ( $prefix, @cmd, $postfix );
}

1;
