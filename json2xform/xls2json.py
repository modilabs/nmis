"""
A Python script to convert excel files into JSON.
"""

from xlrd import open_workbook
import json
import sys

SURVEY = "survey"
CHOICES = "choices"
CHOICE_LIST_NAME = "list name"
TEXT = "text"
TEXT_PREFACE = TEXT + ":"
TYPE = "type"

def _step1(path):
    """
    Return
    {
    "sheet1.name" : [
    {col1.header : value[2,1], col2.header : value[2,2]}, ...
    ]
    "sheet2.name" : [ ...
    ]
    }
    """
    workbook = open_workbook(path)
    result = {}
    for sheet in workbook.sheets():
        result[sheet.name] = []
        for row in range(1,sheet.nrows):
            row_dict = {}
            for column in range(0,sheet.ncols):
                key = sheet.cell(0,column).value
                value = sheet.cell(row,column).value
                if value:
                    row_dict[key] = value
            if row_dict: result[sheet.name].append(row_dict)
    return result

def _clean_text(pyobj):
    for dicts in pyobj.values():
        for d in dicts:
            text = {}
            for k, v in d.items():
                if k.startswith(TEXT_PREFACE):
                    text[k[len(TEXT_PREFACE):]] = v
                    del d[k]
            assert TEXT not in d
            if text: d[TEXT] = text

def _clean_choice_lists(pyobj):
    choice_list = pyobj[CHOICES]
    choices = {}
    for choice in choice_list:
        list_name = choice.pop(CHOICE_LIST_NAME)
        if list_name in choices: choices[list_name].append(choice)
        else: choices[list_name] = [choice]
    pyobj[CHOICES] = choices

def _insert_choice_lists(pyobj):
    survey = pyobj[SURVEY]
    for i in range(len(survey)):
        if survey[i][TYPE].startswith("select"):
            q_type, list_name = survey[i][TYPE].split(" from ")
            survey[i][TYPE] = q_type
            assert "choices" not in survey[i]
            survey[i]["choices"] = pyobj[CHOICES][list_name]

def xls2json(path):
    pyobj = _step1(path)
    _clean_text(pyobj)
    _clean_choice_lists(pyobj)
    _insert_choice_lists(pyobj)
    return json.dumps(pyobj[SURVEY], indent=4)

if __name__ == '__main__':
    print xls2json(sys.argv[1])
