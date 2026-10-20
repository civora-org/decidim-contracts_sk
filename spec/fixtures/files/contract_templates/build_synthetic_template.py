#!/usr/bin/env python3
"""Builds synthetic-template.docx for the S1 toolchain spike (civora-platform#211).

Everything in the output is invented: "Obec Vzorova", fake names, fake IDs. No real
town, person or contract data. Run: python3 build_synthetic_template.py
"""
import zipfile
from xml.sax.saxutils import escape

W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'


def field(expr):
    """A complex MERGEFIELD, the form Word writes: begin / instrText / separate / result / end."""
    return (
        '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
        f'<w:r><w:instrText xml:space="preserve"> MERGEFIELD {expr} \\* MERGEFORMAT </w:instrText></w:r>'
        '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
        f'<w:r><w:t>«{escape(expr)}»</w:t></w:r>'
        '<w:r><w:fldChar w:fldCharType="end"/></w:r>'
    )


def text(t, bold=False):
    rpr = '<w:rPr><w:b/></w:rPr>' if bold else ''
    return f'<w:r>{rpr}<w:t xml:space="preserve">{escape(t)}</w:t></w:r>'


def para(*runs, style=None):
    ppr = f'<w:pPr><w:pStyle w:val="{style}"/></w:pPr>' if style else ''
    return f'<w:p>{ppr}{"".join(runs)}</w:p>'


def cell(*paras, width=3000):
    return f'<w:tc><w:tcPr><w:tcW w:w="{width}" w:type="dxa"/></w:tcPr>{"".join(paras)}</w:tc>'


def row(*cells):
    return f'<w:tr>{"".join(cells)}</w:tr>'


BORDERS = ''.join(
    f'<w:{s} w:val="single" w:sz="4" w:space="0" w:color="000000"/>'
    for s in ('top', 'left', 'bottom', 'right', 'insideH', 'insideV')
)


def table(*rows):
    return f'<w:tbl><w:tblPr><w:tblW w:w="9000" w:type="dxa"/><w:tblBorders>{BORDERS}</w:tblBorders></w:tblPr>{"".join(rows)}</w:tbl>'


# Parties table: person fields (kupujuci_*) are the ones redaction must hide.
parties = table(
    row(cell(para(text('Predávajúci', True))), cell(para(text('Kupujúci', True)))),
    row(
        cell(para(field('=org_nazov')), para(text('IČO: '), field('=org_ico')), para(field('=org_adresa'))),
        cell(para(field('=kupujuci_meno')), para(text('Adresa: '), field('=kupujuci_adresa')), para(text('Rodné číslo: '), field('=kupujuci_rc'))),
    ),
)

# Table-row loop (sablon RowBlock): the start and end fields sit in their OWN rows, the
# data row in between is repeated. Start and end in the same row would not loop.
items = table(
    row(cell(para(text('Položka', True)), width=4500), cell(para(text('Suma (EUR)', True)), width=4500)),
    row(cell(para(field('polozky:each(p)')), width=4500), cell(para(), width=4500)),
    row(cell(para(field('=p.nazov')), width=4500), cell(para(field('=p.suma')), width=4500)),
    row(cell(para(field('polozky:endEach')), width=4500), cell(para(), width=4500)),
)

body = ''.join([
    para(text('ZMLUVA O DIELO č. '), field('=cislo_zmluvy'), style='Title'),
    para(text('uzatvorená medzi zmluvnými stranami v zmysle § 536 Obchodného zákonníka.')),
    parties,
    para(text('')),
    para(text('Predmet zmluvy', True)),
    para(text('Zhotoviteľ sa zaväzuje vykonať dielo "'), field('=predmet'), text('" pre objednávateľa '), field('=org_nazov'), text('.')),
    para(text('Táto zmluva č. '), field('=cislo_zmluvy'), text(' nadobúda účinnosť dňom '), field('=datum_ucinnosti'), text('.')),
    items,
    para(text('Celková cena: '), field('=suma_celkom'), text(' EUR (slovom: '), field('=suma_slovom'), text(').')),
    # Optional block (sablon ParagraphBlock): control fields stand alone in their own paragraphs.
    para(field('priloha:if')),
    para(text('Neoddeliteľnou súčasťou zmluvy je príloha: '), field('=priloha.nazov'), text('.')),
    para(text('Kupujúci '), field('=kupujuci_meno'), text(' potvrdzuje prevzatie.')),
    para(field('priloha:endIf')),
    para(text('Žltý koník úpäl ďábelské ódy. Ľščťžýáíé ÄÖÜ.')),
    '<w:sectPr><w:headerReference w:type="default" r:id="rIdH"/><w:footerReference w:type="default" r:id="rIdF"/>'
    '<w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>',
])

document = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {W}><w:body>{body}</w:body></w:document>'
header = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:hdr {W}>' + para(field('=org_nazov'), text(' | IČO '), field('=org_ico'), text(' | zmluva '), field('=cislo_zmluvy')) + '</w:hdr>'
page_field = (
    '<w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>'
    '<w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>1</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r>'
)
footer = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:ftr {W}>' + para(field('=org_nazov'), text(' – strana '), page_field) + '</w:ftr>'

styles = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {W}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Liberation Serif" w:hAnsi="Liberation Serif" w:cs="Liberation Serif"/><w:sz w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style><w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="32"/></w:rPr></w:style></w:styles>'

content_types = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/><Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/><Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/></Types>'''

rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/></Relationships>'''

doc_rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rIdS" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rIdH" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/><Relationship Id="rIdF" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/></Relationships>'''

# Metadata carries FAKE author/company on purpose: the sanitizer must strip them.
core = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>Vzorová zmluva</dc:title><dc:creator>Fiktívny Úradník Metadátový</dc:creator><cp:lastModifiedBy>Fiktívny Úradník Metadátový</cp:lastModifiedBy><dcterms:created xsi:type="dcterms:W3CDTF">2026-01-01T00:00:00Z</dcterms:created></cp:coreProperties>'''
app = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>Synthetic</Application><Company>Fiktívna Spoločnosť Metadátová s.r.o.</Company></Properties>'''

with zipfile.ZipFile('synthetic-template.docx', 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('[Content_Types].xml', content_types)
    z.writestr('_rels/.rels', rels)
    z.writestr('word/document.xml', document)
    z.writestr('word/_rels/document.xml.rels', doc_rels)
    z.writestr('word/styles.xml', styles)
    z.writestr('word/header1.xml', header)
    z.writestr('word/footer1.xml', footer)
    z.writestr('docProps/core.xml', core)
    z.writestr('docProps/app.xml', app)
print('wrote synthetic-template.docx')
