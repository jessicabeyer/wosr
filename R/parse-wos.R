parse_wos <- function(all_resps) {
  pbapply::pblapply(all_resps, one_parse)
}

# Parse one resposnes and place results into list
one_parse <- function(response) {

  # Create html parse tree
  doc <- get_xml(response)

  # Get nodes corresponding to each publication
  doc_list <- xml_find_all(doc, xpath = "//rec")

  # Parse data
  list(
    pub_parselist = parse_gen_pub_data(doc_list),
    author_parselist = parse_author_node_data(doc_list),
    address_parselist = parse_address_node_data(doc_list),
    grant_parselist = parse_grant_data(doc_list)
  )
}

# Function to pull out data from elements (and their attributes) that don't
# require we care about their ancestor nodes (beyond the fact that they exist
# in a given rec node)
parse_gen_pub_data <- function(doc_list) {

  pub_els_xpath <- c(
    ut = ".//uid[1]", # document id
    title = ".//summary//title[@type='item'][1]", # title
    journal = ".//summary//title[@type='source'][1]", # journal
    doc_type = ".//summary//doctype", # doc type
    abstract = ".//fullrecord_metadata//p[ancestor::abstract_text]", # abstract
    jsc = ".//fullrecord_metadata//subject[@ascatype='traditional']", # JSCs
    keyword = ".//fullrecord_metadata//keyword", # keywords
    keywords_plus = ".//static_data//keywords_plus/keyword", # keywords plus
    page_count = ".//summary//page/@page_count"
  )
  pub_els_out <- parse_els_apply(doc_list, xpath = pub_els_xpath)

  pub_atrs_xpath <- c(
    sortdate = ".//summary//pub_info[1]", # publication's pub date
    value = ".//dynamic_data//identifier[@type='doi'][1]", # publication's DOI
    local_count = ".//citation_related//silo_tc[1]" # times cited
  )
  atr_list <- parse_atrs_apply(doc_list, xpath = pub_atrs_xpath)

  bind_el_atr(pub_els_out, atr_list = atr_list)
}

# For each pub, find the nodes containing author data and extract the relevant
# child node values and attributes from those nodes
parse_author_node_data <- function(doc_list) {

  author_list <- split_nodes(
    doc_list,
    xpath = ".//summary//names//name[@role='author' and string-length(@seq_no)>0]"
  )
  message_long_parse(author_list, "authors")

  el_xpath <- c(
    display_name = "display_name[1]", # display name (e.g., baker, chris)
    first_name = "first_name[1]",
    last_name = "last_name[1]",
    email = "email_addr[1]" # author's email
  )
  atr_xpath <- c(
    seq_no = ".", # author's listing sequence
    daisng_id = ".", # author's DaisNG ID
    addr_no = "." # Authors address number, for linking to address data
  )

  parse_deep(author_list, el_xpath = el_xpath, atr_xpath = atr_xpath)
}

# For each pub, find the nodes containing address data and extract the relevant
# child node values and attributes from those nodes
parse_address_node_data <- function(doc_list) {

  address_list <- split_nodes(
    doc_list,
    xpath = ".//fullrecord_metadata//addresses/address_name/address_spec"
  )
  message_long_parse(address_list, "addresses")

  el_xpath <- c(
    org_pref = "organizations/organization[@pref='Y'][1]", # preferred name of org
    org = "organizations/organization[not(@pref='Y')][1]", # regular name of org
    city = "city[1]", # org city
    state = "state[1]", # org state
    country = "country[1]" # org country
  )
  atr_xpath <- c(addr_no = ".")

  parse_deep(address_list, el_xpath = el_xpath, atr_xpath = atr_xpath)
}

parse_grant_data <- function(doc_list) {
  grant_list <- split_nodes(doc_list, ".//fund_ack/grants/grant")
  el_xpath <- c(grant_agency = "grant_agency", grant_id = "grant_ids/grant_id")
  parse_deep_grants(grant_list, el_xpath = el_xpath)
}

## utility parsing functions
get_xml <- function(response) {
  raw_xml <- httr::content(response, as = "text")
  unescaped_xml <- unescape_xml(raw_xml)
  unescaped_xml <- paste0("<x>", unescaped_xml, "</x>")
  read_html(unescaped_xml)
}

unescape_xml <- function(x) {
  x <- gsub("&lt;", "<", x)
  x <- gsub("&gt;", ">", x)
  gsub("&amp;", "&", x)
}

split_nodes <- function(doc_list, xpath)
  lapply(doc_list, xml_find_all, xpath = xpath)

parse_deep <- function(entity_list, el_xpath, atr_xpath) {
  lapply(entity_list, function(x) {
    one_ent_data <- lapply(x, function(q) {
      els <- parse_els(q, xpath = el_xpath)
      atrs <- parse_atrs(q, xpath = atr_xpath)
      unlist(c(els, atrs))
    })
    do.call(rbind, one_ent_data)
  })
}

parse_deep_grants <- function(entity_list, el_xpath) {
  lapply(entity_list, function(x) {
    one_ent_data <- lapply(x, function(q) {
      temp <- parse_els(q, xpath = el_xpath)
      num_ids <- length(temp$grant_id)
      if (num_ids >= 2) temp$grant_agency <- rep(temp$grant_agency, num_ids)
      do.call(cbind, temp)
    })
    do.call(rbind, one_ent_data)
  })
}

parse_els_apply <- function(doc_list, xpath)
  lapply(doc_list, parse_els, xpath = xpath)

parse_els <- function(doc, xpath)
  lapply(xpath, function(x) parse_el_txt(doc, xpath = x))

parse_el_txt <- function(doc, xpath) {
  txt <- xml_text(xml_find_all(doc, xpath = xpath))
  na_if_missing(txt)
}

parse_atrs_apply <- function(doc_list, xpath)
  lapply(doc_list, parse_atrs, xpath = xpath)

parse_atrs <- function(doc, xpath) {
  lapply2(names(xpath), function(x) {
    el <- xml_find_all(doc, xpath = xpath[[x]])
    atr_out <- xml_attr(el, attr = x)
    na_if_missing(atr_out)
  })
}

na_if_missing <- function(x) if (is.null(x) || length(x) == 0) NA else x

bind_el_atr <- function(el_list, atr_list)
  lapply(seq_along(el_list), function(x) c(el_list[[x]], atr_list[[x]]))

message_long_parse <- function(list, entity) {
  num_ents <- vapply(list, length, numeric(1))
  if (any(num_ents >= 100)) {
    message(
      "At least one of your publications has more than 100 ", entity,
      " listed on it. Parsing the data from these publications will take",
      " some time."
    )
  }
}
